#!/usr/bin/env python3
"""Summarise the clean reproduction batch (runs named repro_<config>_r<i>).

Writes repro_runs.csv (one row per run) and prints per-configuration counts.
Usage: python3 -I scripts/summarise_batch.py   (from testbed/)
"""
import csv, glob, json, os, re, subprocess, sys
from datetime import datetime

T = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNS = sorted(glob.glob(f"{T}/twoamf/runs/repro_*") + glob.glob(f"{T}/open5gs-twoamf/runs/repro_*"))

def read(p):
    try:
        return open(p, errors="replace").read()
    except FileNotFoundError:
        return ""

def ue_times(ue):
    """Return (n_success, latency_ms_after_move) from a UERANSIM log."""
    ev = []
    for line in ue.splitlines():
        m = re.match(r"\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\] \[nas\] \[\w+\] (.*)", line)
        if not m:
            continue
        t = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f")
        msg = m.group(2)
        if re.search(r"Registration is successful", msg):
            ev.append((t, "ok", msg))
        elif re.match(r"Sending (Initial|Mobility) Registration", msg):
            ev.append((t, "send", msg))
    oks = [e for e in ev if e[1] == "ok"]
    if not oks:
        return 0, None, None, ""
    first_ok = oks[0][0]
    after = [e for e in ev if e[0] > first_ok]
    sends = [e for e in after if e[1] == "send"]
    later_ok = [e for e in after if e[1] == "ok"]
    lat = last = None
    if sends and later_ok:
        lat = round((later_ok[0][0] - sends[0][0]).total_seconds() * 1000, 1)
        prior = [e for e in sends if e[0] <= later_ok[0][0]]
        last = round((later_ok[0][0] - prior[-1][0]).total_seconds() * 1000, 1)
    kind = later_ok[0][2].split()[0] if later_ok else ""
    return len(oks), lat, last, kind

CAUSE = {"IMPLICITY_DEREGISTERED": "10", "UNSPECIFIED_PROTOCOL_ERROR": "111",
         "SEMANTICALLY_INCORRECT_MESSAGE": "95", "UE_IDENTITY_CANNOT_BE_DERIVED_FROM_NETWORK": "9"}

def causes(ue):
    """Reject causes as reported by the UE (a protected Registration Reject is not decodable in the pcap)."""
    return ";".join(CAUSE.get(c, c) for c in re.findall(r"Registration failed \[(\w+)\]", ue))

rows = []
for run in RUNS:
    name = os.path.basename(run)
    m = re.match(r"repro_(\w+?)_r(\d+)$", name)
    cfg, i = m.group(1), int(m.group(2))
    ue = read(f"{run}/ue.log")
    n_ok, lat, last, kind = ue_times(ue)
    row = {"config": cfg, "run": i, "ue_successes": n_ok, "re_registered_after_move": n_ok >= 2,
           "accepted_procedure": kind, "latency_ms": lat, "final_attempt_ms": last, "reject_causes": causes(ue)}
    if cfg.startswith("f5"):
        a1, a2 = read(f"{run}/amf1.log"), read(f"{run}/amf2.log")
        st = read(f"{run}/03_after_move_state.txt")
        serving = "amf1" if cfg == "f5ctl" else "amf2"
        xfer = re.findall(r"\| (\d{3}) \|[^|]*\| POST +\| /namf-comm/v1/ue-contexts/[^ ]*/transfer \|", a1)
        row["transfer_http"] = ",".join(xfer)
        g0 = re.search(r"New AmfUe \[supi:\]\[guti:(\w+)\]", a1)
        row["guti_initial"] = g0.group(1) if g0 else ""
        oam = re.search(rf"== {serving} OAM\n(.*)\n", st)
        try:
            ctx = json.loads(oam.group(1)) if oam else None
        except json.JSONDecodeError:
            ctx = None
        row["guti_final"] = ctx[0]["Guti"] if ctx else ""
        sub = re.search(rf"== {serving} PATCH sub 1\n.*HTTP (\d+)", st)
        row["subscription_at_serving_amf"] = sub.group(1) if sub else ""
        n = re.search(r"== notify sink bytes\n\s*(\d+)", st)
        row["notify_bytes"] = n.group(1) if n else ""
    else:
        a1, a2 = read(f"{run}/amf1.log"), read(f"{run}/amf2.log")
        xfer = re.findall(r"\[(\d{3}):POST\] \S*/transfer \(", a2)
        row["transfer_http"] = ",".join(xfer)
        g1 = re.findall(r"5G-S_GUTI\[AMF_ID:0x(\w+),M_TMSI:0x(\w+)\] \(\.\./src/amf/gmm-build\.c", a1)
        g2 = re.findall(r"5G-S_GUTI\[AMF_ID:0x(\w+),M_TMSI:0x(\w+)\] \(\.\./src/amf/gmm-build\.c", a2)
        row["guti_initial"] = "-".join(g1[0]) if g1 else ""
        row["guti_final"] = "-".join(g2[-1]) if g2 else ""
        row["subscription_at_serving_amf"] = "n/a"
        row["notify_bytes"] = "n/a"
    row["guti_changed"] = bool(row["guti_final"]) and row["guti_final"] != row["guti_initial"]
    rows.append(row)

cols = ["config", "run", "re_registered_after_move", "accepted_procedure", "latency_ms", "final_attempt_ms", "reject_causes",
        "transfer_http", "guti_initial", "guti_final", "guti_changed", "subscription_at_serving_amf",
        "notify_bytes", "ue_successes"]
out = f"{T}/repro_runs.csv"
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    for r in sorted(rows, key=lambda r: (r["config"], r["run"])):
        w.writerow({c: r.get(c, "") for c in cols})

print(f"wrote {out} ({len(rows)} runs)")
by = {}
for r in rows:
    by.setdefault(r["config"], []).append(r)
for cfg, rs in sorted(by.items()):
    ok = sum(r["re_registered_after_move"] for r in rs)
    lats = sorted(r["latency_ms"] for r in rs if r["latency_ms"] is not None and r["re_registered_after_move"])
    med = lats[len(lats) // 2] if lats else None
    fl = sorted(r["final_attempt_ms"] for r in rs if r["final_attempt_ms"] is not None and r["re_registered_after_move"])
    fmed = fl[len(fl) // 2] if fl else None
    caus = sorted({r["reject_causes"] for r in rs})
    gch = sum(r["guti_changed"] for r in rs)
    subs = sorted({r["subscription_at_serving_amf"] for r in rs})
    print(f"{cfg:12s} n={len(rs):2d} re-registered={ok:2d} median_latency_ms={med} median_final_attempt_ms={fmed} "
          f"guti_changed={gch} causes={caus} sub@serving={subs} transfer={sorted({r['transfer_http'] for r in rs})}")
