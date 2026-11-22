#!/usr/bin/env python3
"""Finding 2, consumer side: summarise run_exp2_notify.sh runs.

Per run:
  - transfer: reason, and whether the UEContextTransfer response carried the event subscription
    (eventSubscriptionList with the consumer's subsChangeNotifyUri);
  - sink: TCP connections to the subscriber's notification endpoint (probe:9000), before and after the move;
    the pre-move one is the AMF2 self-test;
  - consumer view after the move: HTTP status of PATCH on the original subscription at AMF1 and AMF2, and of a new
    UE-specific subscription (immediate LOCATION_REPORT) at AMF1 and AMF2; serving AMF and TAC.
Usage: python3 -I summarise_notify.py <runs-dir> <run> [...]   -> CSV on stdout
"""
import csv, os, re, subprocess, sys

AMF = {"10.100.200.16": "AMF1", "10.100.200.17": "AMF2"}
SINK = "10.100.200.50"


def tshark(run_dir, args):
    cmd = ["docker", "run", "--rm", "-v", f"{os.path.abspath(run_dir)}:/in:ro", "nicolaka/netshoot",
           "tshark", "-r", "/in/sbi.pcap", "-d", "tcp.port==8000,http2"] + args
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def http2_text(run_dir, flt):
    out = []
    for line in tshark(run_dir, ["-Y", flt, "-T", "fields", "-e", "frame.number", "-e", "ip.src", "-e", "ip.dst",
                                 "-e", "http2.data.data"]).splitlines():
        f = (line.split("\t") + ["", "", "", ""])[:4]
        body = b"".join(bytes.fromhex(h.replace(":", "")) for h in f[3].split(",") if h)
        out.append((f[0], f[1], f[2], body.decode("utf-8", "replace")))
    return out


def section(text, head):
    m = re.search(r"== " + re.escape(head) + r"\n(.*?)(?=\n== |\Z)", text, re.S)
    return m.group(1).strip() if m else ""


def code(s):
    m = re.search(r"HTTP (\d{3})", s)
    return m.group(1) if m else ""


def main():
    runs_dir = sys.argv[1]
    w = csv.writer(sys.stdout)
    w.writerow(["run", "mode", "transfer_reason", "transferred_event_subs", "transferred_subs_change_uri",
                "serving_amf", "serving_tac", "sink_conns_before_move", "sink_conns_after_move",
                "patch_sub1_amf1", "patch_sub1_amf2", "new_sub_amf1", "new_sub_amf2", "new_sub_report_tac"])
    for run in sys.argv[2:]:
        d = os.path.join(runs_dir, run)
        t_move = float(open(os.path.join(d, "t_move.txt")).read().strip())
        st = open(os.path.join(d, "03_after_move_state.txt")).read()
        # transfer (AMF2 -> AMF1) request and response bodies
        reason, n_subs, subs_chg = "none", 0, ""
        for _, src, dst, body in http2_text(d, 'frame contains "INIT_REG" || frame contains "MOBI_REG"'):
            m = re.search(r'"reason":"([A-Z_]+)"', body)
            if m and AMF.get(src) == "AMF2":
                reason = m.group(1)
        for _, src, dst, body in http2_text(d, 'frame contains "eventSubscriptionList"'):
            if AMF.get(src) == "AMF1" and AMF.get(dst) == "AMF2":
                n_subs = body.count('"eventNotifyUri"')
                subs_chg = "yes" if "/subs-change" in body else "no"
        # connections to the notification sink
        before = after = 0
        for line in tshark(d, ["-Y", f"ip.dst=={SINK} && tcp.dstport==9000 && tcp.flags.syn==1 && tcp.flags.ack==0",
                               "-T", "fields", "-e", "frame.time_epoch", "-e", "ip.src"]).splitlines():
            t, src = line.split("\t")
            if float(t) < t_move:
                before += 1
            else:
                after += 1
        serving, tac = "", ""
        for a in ("amf1", "amf2"):
            oam = section(st, f"{a} OAM")
            if "imsi-208930000000001" in oam:
                serving = a.upper()
                m = re.search(r'"Tac":"(\d+)"', oam)
                tac = m.group(1) if m else ""
        rep = section(st, "amf1 POST new UE subscription (immediate LOCATION_REPORT)") + \
            section(st, "amf2 POST new UE subscription (immediate LOCATION_REPORT)")
        m = re.search(r'"tai":\{[^}]*\},"tac":"(\d+)"', rep)
        w.writerow([run, "control" if "ctl" in run else "amf_change", reason, n_subs, subs_chg, serving, tac,
                    before, after,
                    code(section(st, "amf1 PATCH sub 1")), code(section(st, "amf2 PATCH sub 1")),
                    code(section(st, "amf1 POST new UE subscription (immediate LOCATION_REPORT)")),
                    code(section(st, "amf2 POST new UE subscription (immediate LOCATION_REPORT)")),
                    m.group(1) if m else ""])


if __name__ == "__main__":
    main()
