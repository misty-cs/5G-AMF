#!/usr/bin/env python3
"""Summarise experiment 5 (slice-triggered AMF re-allocation with the ch5 patches).

exp5fresh_r*: fresh UE requesting slices A+B; lands on AMF1 (A only) and is re-allocated to AMF2 (A+B).
exp5reg_r*:   UE registered on AMF1 with slice A and an event subscription, then `slice-add` B.
Writes exp5_runs.csv. Usage: python3 -I scripts/summarise_exp5.py (from testbed/)
"""
import csv, glob, json, os, re

T = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAUSE = {"IMPLICITY_DEREGISTERED": "10", "CONGESTION": "22", "UNSPECIFIED_PROTOCOL_ERROR": "111",
         "TA_NOT_ALLOWED": "12"}


def rd(p):
    try:
        return open(p, errors="replace").read()
    except FileNotFoundError:
        return ""


def after(text, marker):
    i = text.find(marker)
    return text[i:] if marker and i >= 0 else text


rows = []
for run in sorted(glob.glob(f"{T}/twoamf/runs/exp5*_r*")):
    name = os.path.basename(run)
    a1, a2, ue, gnb = (rd(f"{run}/{x}.log") for x in ("amf1", "amf2", "ue", "gnb1"))
    reg = "reg_" in name  # exp5reg_r*, exp5r2reg_r*
    if reg:
        trig = rd(f"{run}/03_trigger_time.txt").splitlines()
        ue_after = after(ue, "ch5: slice sst")
    else:
        ue_after = ue
    recv = re.search(r"ch5trace realloc-received (\{.*\})", a2)
    keys = sorted(json.loads(recv.group(1))) if recv else []
    row = {
        "run": name,
        "scenario": "registered UE + slice-add" if reg else "fresh registration",
        "realloc_triggered": "not supported by AMF" in a1,
        "n1_notify_204": bool(re.search(r"\| 204 \|.*n1-message-notify", a2)),
        "gnb_reassociated": "re-allocated from AMF" in gnb,
        "forwarded_fields": " ".join(keys),
        "forwarded_security_ctx": ("seafData" in keys) or ("mmContextList" in keys),
        "forwarded_event_subs": "eventSubscriptionList" in keys,
        "target_reauth": "Send Authentication Request" in after(a2, "n1-message-notify"),
        "ue_registered_after": bool(re.search(r"Registration is successful", ue_after)),
        "ue_reject_causes": ";".join(CAUSE.get(c, c) for c in re.findall(r"Registration failed \[(\w+)\]", ue_after)),
        "transfer_to_amf1": ",".join(re.findall(r"\| (\d{3}) \|[^|]*\| POST +\| /namf-comm/v1/ue-contexts/\S*/transfer", a1)),
        "ausf_400": "Authenticate Request Error: 400" in a2,
    }
    if reg:
        st = rd(f"{run}/04_after_trigger.txt")
        s1 = re.search(r"== amf1 PATCH sub 1\n.*HTTP (\d+)", st)
        s2 = re.search(r"== amf2 PATCH sub 1\n.*HTTP (\d+)", st)
        row["sub_created_amf1"] = " HTTP 201" in rd(f"{run}/01_create_sub_amf1.txt")
        row["sub_at_amf1_after"] = s1.group(1) if s1 else ""
        row["sub_at_amf2_after"] = s2.group(1) if s2 else ""
    rows.append(row)

cols = ["run", "scenario", "realloc_triggered", "n1_notify_204", "gnb_reassociated", "forwarded_security_ctx",
        "forwarded_event_subs", "target_reauth", "ue_registered_after", "ue_reject_causes", "transfer_to_amf1",
        "ausf_400", "sub_created_amf1", "sub_at_amf1_after", "sub_at_amf2_after", "forwarded_fields"]
out = f"{T}/exp5_runs.csv"
with open(out, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    for r in rows:
        w.writerow({c: r.get(c, "") for c in cols})
print(f"wrote {out} ({len(rows)} runs)")
for r in rows:
    print({k: v for k, v in r.items() if k != "forwarded_fields"})
