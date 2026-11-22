#!/usr/bin/env python3
"""Summarise experiment 3 (next registration after the AMF change; runs exp3_*).

Per run:
  periodic_result   outcome of the first periodic registration after the UE is released to idle
  outage_s          time from that periodic registration to the next successful registration
  transfer_after    UEContextTransfer responses triggered after the release (to the old AMF)
  tmsi_ta1          5G-TMSI the UE was given at the first AMF
  tmsi_presented    5G-GUTI/5G-TMSI the UE presents in cleartext in the periodic registration
  linkable          tmsi_presented == tmsi_ta1 (same identifier visible before and after the move)
  guti_end          GUTI the serving AMF holds at the end
Writes exp3_runs.csv. Usage: python3 -I scripts/summarise_exp3.py (from testbed/)
"""
import csv, glob, os, re
from datetime import datetime

T = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def rd(p):
    try:
        return open(p, errors="replace").read()
    except FileNotFoundError:
        return ""

def t_ue(line):
    m = re.match(r"\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\]", line)
    return datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f") if m else None

def t_f5(line):
    m = re.match(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6})", line)
    return datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S.%f") if m else None

def t_o5(line, year):
    m = re.match(r"(\d\d/\d\d \d\d:\d\d:\d\d\.\d+):", line)
    return datetime.strptime(f"{year}/{m.group(1)}", "%Y/%m/%d %H:%M:%S.%f") if m else None

rows = []
for run in sorted(glob.glob(f"{T}/twoamf/runs/exp3_*") + glob.glob(f"{T}/open5gs-twoamf/runs/exp3_*")):
    name = os.path.basename(run)
    if not os.path.exists(f"{run}/ue_after.log"):
        continue
    rel = datetime.strptime(rd(f"{run}/10_release_time.txt").splitlines()[0], "%Y-%m-%d %H:%M:%S")
    o5 = "/open5gs-twoamf/" in run
    ctl = "ctl_" in name
    ue = [(t_ue(l), l) for l in rd(f"{run}/ue_after.log").splitlines() if t_ue(l)]
    after = [(t, l) for t, l in ue if t >= rel]
    per = next(((t, l) for t, l in after if "Sending Periodic Registration" in l), None)
    res, outage = "no periodic registration", None
    if per:
        nxt = next(((t, l) for t, l in after if t >= per[0] and re.search(r"Periodic Registration (is successful|failed)", l)), None)
        if nxt and "failed" in nxt[1]:
            res = "rejected " + re.search(r"failed \[(\w+)\]", nxt[1]).group(1)
        elif nxt:
            res = "accepted"
        ok = next(((t, l) for t, l in after if t >= per[0] and "Registration is successful" in l), None)
        outage = round((ok[0] - per[0]).total_seconds(), 3) if ok else None
    serving_after = rd(f"{run}/amf1_after.log" if ctl else f"{run}/amf2_after.log")
    a1_first = rd(f"{run}/amf1.log")
    if o5:
        yr = rel.year
        g1 = re.search(r"5G-S_GUTI\[AMF_ID:0x(\w+),M_TMSI:0x(\w+)\] \(\.\./src/amf/gmm-build\.c", a1_first)
        tmsi1 = f"{g1.group(1)}-{g1.group(2)}" if g1 else ""
        pres = ""
        for l in serving_after.splitlines():
            t = t_o5(l, yr)
            if t and t >= rel:
                m = re.search(r"5G-S_GUTI\[(?:PLMN_ID:0x\w+,)?AMF_ID:0x(\w+),M_TMSI:0x(\w+)\] \(\.\./src/amf/gmm-handler\.c", l)
                if m:
                    pres = f"{m.group(1)}-{m.group(2)}"
                    break
        ends = re.findall(r"5G-S_GUTI\[AMF_ID:0x(\w+),M_TMSI:0x(\w+)\] \(\.\./src/amf/gmm-build\.c", serving_after)
        gend = "-".join(ends[-1]) if ends else ""
        xfer = [m.group(1) for l in serving_after.splitlines() if (t := t_o5(l, yr)) and t >= rel
                for m in [re.search(r"\[(\d{3}):POST\] \S*/transfer \(", l)] if m]
    else:
        g1 = re.search(r"New AmfUe \[supi:\]\[guti:(\w+)\]", a1_first)
        tmsi1 = g1.group(1) if g1 else ""
        pres = ""
        for l in serving_after.splitlines():
            t = t_f5(l)
            if t and t >= rel:
                m = re.search(r"MobileIdentity5GS: GUTI\[(\w+)\]", l)
                if m:
                    pres = m.group(1)
                    break
        ends = re.findall(r"\b(20893[0-9a-f]{14})\b", serving_after)
        gend = ends[-1] if ends else ""
        a1_after = rd(f"{run}/amf1_after.log")
        xfer = [m.group(1) for l in a1_after.splitlines() if (t := t_f5(l)) and t >= rel
                for m in [re.search(r"\| (\d{3}) \|[^|]*\| POST +\| /namf-comm/v1/ue-contexts/\S*/transfer \|", l)] if m]
    rows.append({"run": name, "periodic_result": res, "outage_s": outage, "transfer_after": ",".join(xfer),
                 "tmsi_ta1": tmsi1, "tmsi_presented": pres,
                 "linkable": bool(pres) and pres == tmsi1,
                 "guti_end": gend})

out = f"{T}/exp3_runs.csv"
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]) if rows else ["run"])
    w.writeheader()
    w.writerows(rows)
print(f"wrote {out} ({len(rows)} runs)")
for r in rows:
    print(r)
