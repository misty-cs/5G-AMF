#!/usr/bin/env python3
"""GUTI repair test: summarise exp3_observer.sh runs (gr_base_*, gr_rep_*, gr_ctl_*).

Per run (logs; radio-link columns from summarise_obs.py on obs.pcap):
  mode               base (fix, AMF change) / repair (fix + GUTI repair, AMF change) / control (repair image, same AMF)
  guti_first         5G-GUTI AMF1 allocated at the first registration (TA 1)
  guti_next_reg      5G-GUTI the UE presents in its next periodic registration (serving AMF's log)
  new_guti           guti_next_reg != guti_first
  guti_amf_id        AMF ID inside guti_next_reg; serving_amf_id is the AMF that serves the UE after the move
  owned_by_serving   guti_amf_id == serving_amf_id
  periodic_result    accepted / rejected <cause> / no periodic registration
  outage_s           periodic registration sent -> next successful registration (UE log)
  transfer_after     UEContextTransfer status codes at AMF1 after the release (a retry at the old AMF)
  radio_*            from summarise_obs.py (N2 + RLS uplink): GUTI in the mobility registration (at_move), in the
                     initial registration that follows a #10 reject (retry), and in the next periodic registration;
                     whether the periodic GUTI equals the one at the move (linkable by identifier); and the gNB
                     whose radio uplink carried the periodic GUTI
Usage (from testbed/): python3 -I scripts/summarise_gutirepair.py [run ...]  -> gutirepair_runs.csv
"""
import csv, glob, os, re, subprocess, sys
from datetime import datetime

T = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUNS = f"{T}/twoamf/runs"
AMF_ID = {"AMF1": "cafe00", "AMF2": "cb0100"}


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


def mode_of(name):
    return "control" if "_ctl_" in name else "repair" if "_rep" in name else "base"


def summarise(run):
    name = os.path.basename(run)
    mode = mode_of(name)
    serving = "AMF1" if mode == "control" else "AMF2"
    rel = datetime.strptime(rd(f"{run}/10_release_time.txt").splitlines()[0], "%Y-%m-%d %H:%M:%S")
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
    g1 = re.search(r"New AmfUe \[supi:\]\[guti:(\w+)\]", rd(f"{run}/amf1.log"))
    guti_first = g1.group(1) if g1 else ""
    guti_next = ""
    for l in rd(f"{run}/{serving.lower()}_after.log").splitlines():
        t = t_f5(l)
        if t and t >= rel:
            m = re.search(r"MobileIdentity5GS: GUTI\[(\w+)\]", l)
            if m:
                guti_next = m.group(1)
                break
    gid = guti_next[5:11] if len(guti_next) >= 11 else ""   # 20893 | amfId (6 hex) | tmsi (8 hex)
    xfer = [m.group(1) for l in rd(f"{run}/amf1_after.log").splitlines() if (t := t_f5(l)) and t >= rel
            for m in [re.search(r"\| (\d{3}) \|[^|]*\| POST +\| /namf-comm/v1/ue-contexts/\S*/transfer \|", l)] if m]
    return {"run": name, "mode": mode, "guti_first": guti_first, "guti_next_reg": guti_next,
            "new_guti": bool(guti_next) and guti_next != guti_first, "guti_amf_id": gid,
            "serving_amf_id": AMF_ID[serving], "owned_by_serving": gid == AMF_ID[serving],
            "periodic_result": res, "outage_s": outage, "transfer_after": ",".join(xfer)}


def radio(names):
    out = subprocess.run([sys.executable, "-I", f"{T}/scripts/summarise_obs.py", RUNS] + names,
                         capture_output=True, text=True).stdout
    rows = list(csv.DictReader(out.splitlines()))
    return {r["run"]: r for r in rows}


def main():
    names = sys.argv[1:] or sorted(os.path.basename(p) for p in glob.glob(f"{RUNS}/gr_*_r*")
                                   if os.path.exists(f"{p}/ue_after.log"))
    rows = [summarise(f"{RUNS}/{n}") for n in names]
    obs = radio(names)
    for r in rows:
        o = obs.get(r["run"], {})
        r["radio_guti_at_move"] = o.get("guti_at_move", "")
        r["radio_guti_retry"] = o.get("guti_next_reg", "")          # initial registration after the #10 reject
        r["radio_guti_periodic"] = o.get("guti_periodic", "")
        r["radio_periodic_same_as_move"] = (o.get("guti_periodic") == o.get("guti_at_move")) if o.get("guti_periodic") else ""
        r["radio_seen_periodic"] = o.get("seen_on_radio_periodic", "")
    out = f"{T}/gutirepair_runs.csv"
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {out} ({len(rows)} runs)")
    for r in rows:
        print(",".join(str(v) for v in r.values()))


if __name__ == "__main__":
    main()
