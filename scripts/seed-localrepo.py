#!/usr/bin/env python3
"""seed-localrepo.py - put the live builds of a partial build's pocknix siblings into build/localrepo.

    scripts/seed-localrepo.py --skip "a b" REPO_URL SOC LOCALREPO DEP...

CI builds only the packages a PR changes, but `makepkg -s` resolves depends= and makedepends=
from [pocknix]/[pocknix-shared] too: a sibling missing from the local repo aborts the build.
Every DEP (and, transitively, its depends) that the live repos carry and --skip does not name is
downloaded into LOCALREPO/shared or LOCALREPO/SOC; build-packages.sh registers what it finds
there. Names the live repos do not carry come from the base and are left alone.
"""
import argparse
import io
import re
import sys
import tarfile
import urllib.request
from pathlib import Path


def fetch(url):
    # the repo's CDN answers 403 to urllib's default User-Agent
    req = urllib.request.Request(url, headers={"User-Agent": "pocknix-ci"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def read_db(raw):
    """name and provides -> (filename, depends) for every package in a repo-add db."""
    index = {}
    with tarfile.open(fileobj=io.BytesIO(raw)) as tar:
        for m in tar.getmembers():
            if not m.name.endswith("/desc"):
                continue
            fields, key = {}, None
            for line in tar.extractfile(m).read().decode().splitlines():
                if line.startswith("%") and line.endswith("%"):
                    key = line.strip("%")
                    fields[key] = []
                elif line and key:
                    fields[key].append(line)
            entry = (fields["FILENAME"][0], [bare(d) for d in fields.get("DEPENDS", [])])
            for name in fields["NAME"] + [bare(p) for p in fields.get("PROVIDES", [])]:
                index.setdefault(name, entry)
    return index


def bare(dep):
    return re.split(r"[<>=:]", dep, maxsplit=1)[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("repo_url")
    ap.add_argument("soc")
    ap.add_argument("localrepo", type=Path)
    ap.add_argument("--skip", default="")
    ap.add_argument("deps", nargs="*")
    a = ap.parse_args()

    repos = {
        "shared": read_db(fetch(f"{a.repo_url}/shared/pocknix-shared.db")),
        a.soc: read_db(fetch(f"{a.repo_url}/{a.soc}/pocknix.db")),
    }
    skip, seen, todo = set(a.skip.split()), set(), [bare(d) for d in a.deps]
    while todo:
        name = todo.pop()
        if name in seen or name in skip:
            continue
        seen.add(name)
        for repo, index in repos.items():
            if name in index:
                filename, depends = index[name]
                dest = a.localrepo / repo / filename
                if not dest.exists():
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(fetch(f"{a.repo_url}/{repo}/{filename}"))
                    print(f"seeded {repo}/{filename}")
                todo.extend(depends)
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
