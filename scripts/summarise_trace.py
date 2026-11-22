#!/usr/bin/env python3
"""Per-field state-use classification for traced free5GC runs (twoamf/runs/trace_*).

For each UeContext field (TS 29.518) it compares:
  source  - AMF1 state at its Registration Accept (ch5trace accept in amf1.log)
  sent    - key present in the UEContextTransfer response (ch5trace received in amf2.log)
  copied  - AMF2 state right after CopyDataFromUeContextModel
  accept  - AMF2 state at Registration Accept
and reports one outcome per field and run. Writes trace_fields.csv.
Usage: python3 -I scripts/summarise_trace.py   (from testbed/)
"""
import csv, glob, json, os, re, collections

T = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# UeContext key -> state key in the trace snapshot
FIELDS = [
    ("supi", "supi"), ("gpsiList", "gpsi"), ("pei", "pei"),
    ("subUeAmbr", "subUeAmbr"), ("subRfsp", "subRfsp"),
    ("restrictedRatList", "restrictedRatList"), ("forbiddenAreaList", "forbiddenAreaList"),
    ("serviceAreaRestriction", "serviceAreaRestriction"),
    ("seafData", "kamfHash"), ("mmContextList", "integrityAlg"),
    ("pcfId", "pcfId"), ("pcfAmPolicyUri", "pcfAmPolicyUri"),
    ("amPolicyReqTriggerList", "amPolicyReqTriggerList"),
    ("eventSubscriptionList", "amfEventSubscriptionsForSupi"),
    ("sessionContextList", "sessionContexts"), ("traceData", "traceData"),
]

def empty(v):
    return v in (None, "", [], {}, 0)

def snaps(log, stage):
    return [json.loads(m) for m in re.findall(rf"ch5trace {stage} (\{{.*\}})\s*$", log, re.M)]

def outcome(src, sent, copied, acc, rejected):
    if not src:
        return "not held by source"
    if rejected:
        return "registration rejected"
    if sent and copied:
        return "transferred and applied" if acc == "same" else "transferred, replaced at target"
    if sent and not copied:
        return "transferred, ignored; restored by re-fetch" if acc else "transferred, ignored; lost"
    return "not transferred; restored by re-fetch" if acc else "not transferred; lost"

rows = []
for run in sorted(glob.glob(f"{T}/twoamf/runs/trace_*")):
    name = os.path.basename(run)
    if not os.path.exists(f"{run}/pcf.log"):
        continue  # run still in progress
    a1 = open(f"{run}/amf1.log", errors="replace").read()
    a2 = open(f"{run}/amf2.log", errors="replace").read()
    ctl = "_ctl_" in name
    src_list = snaps(a1, "accept")
    if not src_list:
        continue
    src = src_list[0]  # AMF1 state at the first registration
    sub_created = " HTTP 201" in open(f"{run}/01_create_sub_amf1.txt").read()
    if ctl:  # same AMF: compare AMF1 first and second accept
        tgt_acc = src_list[1] if len(src_list) > 1 else None
        recv, copied = {}, {}
    else:
        r = re.search(r"ch5trace received (\{.*\})\s*$", a2, re.M)
        recv = json.loads(r.group(1)) if r else {}
        c = snaps(a2, "copied")
        copied = c[0] if c else {}
        acc = snaps(a2, "accept")
        tgt_acc = acc[0] if acc else None
    rejected = tgt_acc is None
    for key, sk in FIELDS:
        s_has = (not empty(src.get(sk))) or (key == "eventSubscriptionList" and sub_created)
        sent = key in recv and not empty(recv.get(key))
        cop = not empty(copied.get(sk))
        if rejected:
            acc_v = None
        elif empty(tgt_acc.get(sk)):
            acc_v = None
        elif cop and tgt_acc.get(sk) == copied.get(sk):
            acc_v = "same"
        else:
            acc_v = "value"
        if ctl:
            res = ("not held by source" if not s_has else "registration rejected" if rejected
                   else "kept (same AMF)" if acc_v else "lost (same AMF)")
        else:
            res = outcome(s_has, sent, cop, acc_v, rejected)
        rows.append({"run": name, "field": key, "source": s_has, "sent": sent, "copied": cop,
                     "at_accept": acc_v or "", "outcome": res})
    g_src = src.get("guti")
    g_tgt = tgt_acc.get("guti") if tgt_acc else None
    rows.append({"run": name, "field": "5G-GUTI", "source": bool(g_src), "sent": "", "copied": "",
                 "at_accept": g_tgt or "", "outcome": ("registration rejected" if not g_tgt else
                                                       "reallocated" if g_tgt != g_src else "old GUTI kept")})

out = f"{T}/trace_fields.csv"
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["run", "field", "source", "sent", "copied", "at_accept", "outcome"])
    w.writeheader()
    w.writerows(rows)
print(f"wrote {out} ({len(rows)} rows)")

groups = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
for r in rows:
    grp = re.sub(r"_r\d+$", "", r["run"])
    groups[grp][r["field"]][r["outcome"]] += 1
for grp, fields in sorted(groups.items()):
    n = len({r["run"] for r in rows if re.sub(r"_r\d+$", "", r["run"]) == grp})
    print(f"\n== {grp} (n={n})")
    for fld, c in fields.items():
        print(f"  {fld:24s} " + "; ".join(f"{k} x{v}" for k, v in c.most_common()))
