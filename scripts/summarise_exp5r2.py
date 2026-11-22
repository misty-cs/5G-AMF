#!/usr/bin/env python3
"""Field-level state use under the UE-triggered (slice) AMF change, patch level realloc2 (runs exp5r2reg_r*).
source = AMF1 state at its Registration Accept (ch5trace accept); sent = UeContext forwarded by N1MessageNotify
(ch5trace realloc-received); target = AMF2 state at Registration Accept. Writes exp5r2_fields.csv."""
import collections, csv, glob, json, os, re
T = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIELDS = [("supi","supi"),("gpsiList","gpsi"),("pei","pei"),("subUeAmbr","subUeAmbr"),("subRfsp","subRfsp"),
          ("restrictedRatList","restrictedRatList"),("forbiddenAreaList","forbiddenAreaList"),
          ("serviceAreaRestriction","serviceAreaRestriction"),("seafData","kamfHash"),("mmContextList","integrityAlg"),
          ("pcfId","pcfId"),("pcfAmPolicyUri","pcfAmPolicyUri"),("eventSubscriptionList","amfEventSubscriptionsForSupi"),
          ("traceData","traceData")]
empty = lambda v: v in (None, "", [], {}, 0)
def snaps(log, stage): return [json.loads(m) for m in re.findall(rf"ch5trace {stage} (\{{.*\}})\s*$", log, re.M)]
rows = []
for run in sorted(glob.glob(f"{T}/twoamf/runs/exp5r2reg_r*")):
    name = os.path.basename(run)
    a1, a2 = open(f"{run}/amf1.log", errors="replace").read(), open(f"{run}/amf2.log", errors="replace").read()
    src = (snaps(a1, "accept") or [{}])[0]
    r = re.search(r"ch5trace realloc-received (\{.*\})", a2); sent = json.loads(r.group(1)) if r else {}
    tgt = (snaps(a2, "accept") or [None])[0]
    sub_created = " HTTP 201" in open(f"{run}/01_create_sub_amf1.txt").read()
    for key, sk in FIELDS:
        s_has = (not empty(src.get(sk))) or (key == "eventSubscriptionList" and sub_created)
        is_sent = not empty(sent.get(key))
        if tgt is None: out = "UE not registered at target"
        elif not s_has: out = "not held by source"
        else:
            at = not empty(tgt.get(sk))
            if is_sent and key in ("pcfAmPolicyUri", "pcfId", "supi", "pei"):
                out = ("transferred and applied" if tgt.get(sk) == sent.get(key) else "transferred, replaced at target") if at else "transferred, not applied (lost)"
            elif is_sent: out = "transferred and applied" if at else "transferred, not applied (lost)"
            else: out = "not transferred; restored by re-fetch" if at else "not transferred; lost"
        rows.append({"run": name, "field": key, "outcome": out})
    g1, g2 = src.get("guti"), (tgt or {}).get("guti")
    rows.append({"run": name, "field": "5G-GUTI", "outcome": "UE not registered at target" if not g2 else ("old GUTI kept" if g2 == g1 else "reallocated")})
out = f"{T}/exp5r2_fields.csv"
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["run", "field", "outcome"]); w.writeheader(); w.writerows(rows)
print(f"wrote {out} ({len(rows)} rows, {len({r['run'] for r in rows})} runs)")
agg = collections.defaultdict(collections.Counter)
for r in rows: agg[r["field"]][r["outcome"]] += 1
for fld, c in agg.items(): print(f"  {fld:24s} " + "; ".join(f"{k} x{v}" for k, v in c.most_common()))
