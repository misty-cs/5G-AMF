#!/usr/bin/env python3
"""Summarise the Open5GS user-plane runs: ping replies before/after the move, gap, and core-side events.
Usage: python3 -I summarise_pdu_traffic.py <runs-dir> <run> [...]  -> CSV on stdout"""
import csv, os, re, sys
w = csv.writer(sys.stdout)
w.writerow(["run", "mode", "replies_before_move", "replies_after_move", "first_reply_after_move_s",
            "ue_mobility_registration", "ue_service_request", "smf_release_seen", "accept_pdu_status_0000",
            "tun_up_after", "container_start_times",
            "replies_after_move_plus_1s", "resume_s", "ue_uplink_pending", "reactivation_result_sent"])
for run in sys.argv[2:]:
    d = os.path.join(sys.argv[1], run)
    rd = lambda f: open(os.path.join(d, f), errors="replace").read() if os.path.exists(os.path.join(d, f)) else ""
    m = float(rd("t_move.txt").strip() or 0)
    rep = [float(x) for x in re.findall(r"\[(\d+\.\d+)\] \d+ bytes from", rd("ping.log"))]
    before = [t for t in rep if t < m]; after = [t for t in rep if t >= m]
    ue, smf, amf2, amf1 = rd("ue.log"), rd("smf.log"), rd("amf2.log"), rd("amf1.log")
    meta = rd("00_meta.txt")
    starts = ";".join(l.split()[1][11:19] for l in meta.splitlines() if l.startswith("/o5-"))
    mm = re.search(r"^MODE=(\S+)", meta, re.M)
    mode = {"change": "amf_change", "control": "control", "ctlmob": "control_mobility_reg"}.get(mm.group(1) if mm else "", "control" if "control" in run else "amf_change")
    w.writerow([run, mode, len(before), len(after),
                f"{after[0]-m:.2f}" if after else "",
                "Mobility Registration is successful" in ue, "Service Accept received" in ue,
                bool(re.search(r"sm-contexts/\d+/release", amf1 + amf2)),
                "PDU Session Status : 0000" in amf2 + amf1,
                "UP" in rd("tun_after.txt"), starts,
                # added 2026-11-22: replies in flight at the move are excluded by the 1 s / 0.5 s thresholds
                len([t for t in after if t >= m + 1.0]),
                next((f"{t-m:.2f}" for t in after if t >= m + 0.5), ""),
                "pending[true]" in ue,
                "PDU Session Reactivation Result" in amf2 + amf1])
