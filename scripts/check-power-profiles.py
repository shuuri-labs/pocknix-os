#!/usr/bin/env python3
# Build-time gate for pocknix-perfd's factory profiles: a broken factory file must fail here,
# never on a device. Runs the daemon's own parser against the recorded per-SoC frequency lists.
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PKG = os.path.join(ROOT, "packages/shared/pocknix-bsp-common")
sys.dont_write_bytecode = True  # keep __pycache__ out of the package dir
sys.path.insert(0, PKG)
import pocknix_perf as pp  # noqa: E402

errors = []


def check(cond, msg):
    if not cond:
        errors.append(msg)


def load_freqs(soc):
    cpu, gpu = {}, []
    with open(os.path.join(PKG, "freqs", f"{soc.lower()}.txt")) as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            name, *vals = line.split()
            if name == "gpu":
                gpu = [int(v) for v in vals]
            else:
                cpu[name] = [int(v) for v in vals]
    return cpu, gpu


try:
    factory = pp.load_factory(open(os.path.join(PKG, "power-profiles.conf")).read())
except pp.FactoryError as e:
    print(f"power-profiles.conf: {e}")
    sys.exit(1)

eff, warns = pp.layer_override(factory, None)
check(not warns, f"empty override produced warnings: {warns}")

socs = set(factory["tables"]) | {s for _, s in factory["overlays"]}
for soc in sorted(socs):
    try:
        cpu, gpu = load_freqs(soc)
    except OSError:
        errors.append(f"{soc}: no freqs/{soc.lower()}.txt to validate its tables against")
        continue
    for level, caps in factory["tables"].get(soc, {}).items():
        for policy, khz in caps.items():
            check(policy in cpu, f"{soc}.{level}: {policy} is not a cpufreq policy")
            check(khz in cpu.get(policy, []), f"{soc}.{level}: {policy}={khz} is not an available frequency")
        check(set(caps) == set(cpu), f"{soc}.{level}: covers {sorted(caps)}, SoC has {sorted(cpu)}")
    for pid in factory["order"]:
        t = pp.resolve(eff, pid, soc, cpu, gpu)
        check(all(t["cpu_max"][p] in cpu[p] for p in cpu), f"{soc}/{pid}: CPU cap off the OPP table")
        check(gpu[0] <= t["gpu_min"] <= t["gpu_max"] <= gpu[-1], f"{soc}/{pid}: GPU range {t}")

# Override semantics: a bad profile keeps its factory definition, a bad file is ignored.
pid = factory["order"][0]
for name, text, want_warn in [
    ("bad value", f"[profile.{pid}]\ngpu_max = 7\n", True),
    ("unknown key", f"[profile.{pid}]\nturbo = yes\n", True),
    ("unknown profile", "[profile.nope]\nfan = quiet\n", True),
    ("syntax error", "[profile\nfan quiet\n", True),
    ("table override", "[underclock.SM8550.small]\npolicy0 = 1\n", True),
    ("valid", f"[profile.{pid}]\nfan = moderate\n", False),
]:
    out, w = pp.layer_override(factory, text)
    check(bool(w) == want_warn, f"override '{name}': warnings {w}")
    if want_warn:
        check(out["profiles"] == factory["profiles"], f"override '{name}' changed the profiles")
        check(out["tables"] == factory["tables"], f"override '{name}' changed the tables")
    else:
        check(out["profiles"][pid]["fan"] == "moderate", "valid override not applied")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print(f"power profiles ok ({len(factory['order'])} profiles, {', '.join(sorted(socs))})")
