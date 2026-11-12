#!/usr/bin/env python3
# Build-time gate for code comments: a comment must stay true about the code next to it and short,
# so this fails on (1) a repo path that no longer exists, (2) lineage or validation-status wording,
# which belongs in PATCHES.md, (3) a version, pkgrel, commit hash or date a ledger owns, (4) a
# pointer into the maintainer's notes: repo files are the only thing a comment may point at, and
# (5) a block over 2 lines outside the file's leading header. Exceptions go in check-comments.allow
# as "<path glob> :: <regex>" or "<path glob> :: <kind> :: <regex>", one per line. Each names one
# comment: a regex that matches any line refuses to load, and a line that exempts nothing or
# more than USE_CAP lines, or a long-comment line on a glob or covering two blocks in a file, fails.
import collections
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


class AllowError(ValueError):
    pass


# Texts any comment line could be: a regex that matches one of them exempts every comment.
CATCH_ALL = ("", "#", "//", "x", "# x",
             "# The quick brown fox jumps over the lazy dog: 0-9, a/b.c (d=e).")


def parse_allow(lines, path):
    """(glob, kind or None, regex, lineno). A malformed or catch-all line is an error."""
    rules = []
    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = [f.strip() for f in line.split(" :: ")]
        if len(fields) == 2:
            glob, kind, regex = fields[0], None, fields[1]
        elif len(fields) == 3 and fields[1] in KINDS:
            glob, kind, regex = fields
        else:
            raise AllowError("%s:%d: expected '<glob> :: <regex>' or '<glob> :: <kind> :: <regex>'"
                             % (path, n))
        if not glob or not regex:
            raise AllowError("%s:%d: empty glob or regex" % (path, n))
        try:
            rx = re.compile(regex)
        except re.error as e:
            raise AllowError("%s:%d: bad regex: %s" % (path, n, e))
        if any(rx.search(p) for p in CATCH_ALL):
            raise AllowError("%s:%d: '%s' matches any comment: name the one it exempts"
                             % (path, n, regex))
        rules.append((glob, kind, rx, n))
    return rules


def load_allow(path):
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as f:
            return parse_allow(f, os.path.relpath(path, ROOT))
    except AllowError as e:
        sys.exit(str(e))


def allowed(rules, path, kind, text):
    """Index of the first rule exempting this hit, or None."""
    for i, (g, k, r, _) in enumerate(rules):
        if fnmatch.fnmatch(path, g) and (k is None or k == kind) and r.search(text):
            return i
    return None


# A rule naming specific comments exempts a handful; past this it is a vague regex in disguise.
USE_CAP = 6


def rule_problems(rules, uses, path):
    """Rules must name specific comments: stale, globbed long-comment and over-cap rules fail."""
    total = collections.Counter()
    for (i, _, _), c in uses.items():
        total[i] += c
    out = []
    for i, (glob, kind, _, n) in enumerate(rules):
        if not total[i]:
            out.append("%s:%d: exempts nothing in the tree: drop the stale exception" % (path, n))
        elif total[i] > USE_CAP:
            out.append("%s:%d: exempts %d comment lines (cap %d): name fewer"
                       % (path, n, total[i], USE_CAP))
        if kind == "long comment" and any(c in glob for c in "*?["):
            out.append("%s:%d: a long-comment exception names one file, not a glob" % (path, n))
    out += ["%s:%d: exempts %d long comments in %s: name one" % (path, rules[i][3], c, rel)
            for (i, rel, kind), c in sorted(uses.items()) if kind == "long comment" and c > 1]
    return out


def long_blocks(text, lines):
    """(first lineno, first non-rule text, "N lines") per block of comment lines over LONG_CAP."""
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
            # An allow line names the block by its prose: a bare rule line names nothing.
            first = next((s for _, s in b if not DIVIDER.match(s)), b[0][1])
            yield b[0][0], first, "%d lines" % weight


def scan(root, allow_rules):
    """(hits, uses): uses counts each rule's exemptions per (rule index, file, kind)."""
    hits, uses = [], collections.Counter()

    def report(rel, n, kind, text, what):
        i = allowed(allow_rules, rel, kind, text)
        if i is None:
            hits.append((rel, n, kind, what))
        else:
            uses[(i, rel, kind)] += 1

    for rel in tracked_files(root):
        full = os.path.join(root, rel)
        try:
            text = open(full, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        lines = list(comment_lines(rel, text))
        for n, s, what in long_blocks(text, lines):
            report(rel, n, "long comment", s, what)
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
            for kind, what in found:
                report(rel, n, kind, s, what)
    return hits, uses


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
        # New files (an existing one may be allowed). Long hits expected: the 3-line block (7), the
        # wide pair (15) and the ruled three (18), never the header, the ruled pair or the string.
        long_sh = ["#!/bin/sh", "# header", "# runs", "# long", "# fine", "true",
                   "# a body comment", "# that runs to", "# three lines", "true",
                   "# --- section ---", "# two lines under a rule", "# pass", "true",
                   "# " + "wide " * 20, "# second line", "true",
                   "# --- ruled ---", "# prose one", "# prose two", "# prose three", "true"]
        tpl_py = ["X = \"\"\"", "# inside a string", "\"\"\"", "", "", "def f():", "    pass"]
        for rel, body in (("scripts/selftest-long.sh", long_sh),
                          ("scripts/selftest_tpl.py", tpl_py)):
            with open(os.path.join(tmp, rel), "w", encoding="utf-8") as f:
                f.write("\n".join(body) + "\n")
        # The real tree's own hits are the main scan's to report, not a self-test failure.
        real = set(scan(ROOT, allow_rules)[0])
        hits = [h for h in scan(tmp, allow_rules)[0] if h not in real]
        for h in hits:
            print("  planted -> %s:%d: %s: %s" % h)
        # Allow lines: each catch-all probe refuses to load; vague, globbed, two-block and
        # matchless lines are reported; a ruled block is named by its first prose line.
        loose = [r for r in (".", ".*", "#", "^", "\\S", ".{4}", "^#.{3}", "[a-z]{3}",
                             "^$", "^//", "^x$", "^# x$")
                 if not refused("f :: long comment :: " + r)]
        with open(os.path.join(tmp, "scripts/selftest-many.sh"), "w", encoding="utf-8") as f:
            f.write("".join("true\n# pinned at mesa 26.2.%d\n" % i for i in range(USE_CAP + 1)))
        trial = parse_allow(["scripts/selftest-long.sh :: long comment :: ^# (a body|wide)",
                             "scripts/selftest-long.sh :: long comment :: ^# no such comment",
                             "scripts/selftest-long.sh :: long comment :: ^# prose one",
                             "scripts/selftest-many.sh :: version :: mesa 26",
                             "scripts/selftest-*.sh :: long comment :: ^# three lines"], "t")
        got = rule_problems(trial, scan(tmp, trial)[1], "t")
        want = ["t:2: exempts nothing in the tree: drop the stale exception",
                "t:4: exempts %d comment lines (cap %d): name fewer" % (USE_CAP + 1, USE_CAP),
                "t:5: exempts nothing in the tree: drop the stale exception",
                "t:5: a long-comment exception names one file, not a glob",
                "t:1: exempts 2 long comments in scripts/selftest-long.sh: name one"]
        if loose or got != want:
            print("selftest FAILED: catch-alls loaded: %s; allow problems %s, wanted %s"
                  % (loose, got, want))
            return 1
        caught = ("scripts/does-not-exist.sh", "pocknix-notes", "ported from", "26.2.3", "mesa 26.2")
        kinds = {h[2] for h in hits if h[0] == "scripts/lib.sh" and h[3] in caught}
        kinds |= {h[2] for h in hits if h[0] == "scripts/selftest-long.sh"}
        longs = sorted(h[1] for h in hits if h[0] == "scripts/selftest-long.sh")
        stray = [h for h in hits if h[0] not in ("scripts/lib.sh", "scripts/selftest-long.sh")]
        if kinds != set(KINDS) or longs != [7, 15, 18] or stray:
            print("selftest FAILED: caught %s at long lines %s, wanted %s at [7, 15, 18]; stray %s"
                  % (sorted(kinds), longs, list(KINDS), stray))
            return 1
        print("selftest: each planted comment and allow line caught, nothing else flagged")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def refused(line):
    try:
        parse_allow([line], "t")
    except AllowError:
        return True
    return False


def main(argv):
    allow_rules = load_allow(ALLOW_FILE)
    if "--selftest" in argv:
        return selftest(allow_rules)
    hits, uses = scan(ROOT, allow_rules)
    problems = rule_problems(allow_rules, uses, os.path.relpath(ALLOW_FILE, ROOT))
    for rel, n, kind, what in hits:
        print("%s:%d: %s: %s" % (rel, n, kind, what))
    if hits:
        print("%d stale-looking comment(s); fix the comment or add a line to scripts/check-comments.allow"
              % len(hits))
    for p in problems:
        print(p)
    return 1 if hits or problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
