#!/usr/bin/env python3
"""Observer view of the 5G-GUTI across an AMF change (free5GC), from obs.pcap.

For each run:
  1. From N2 (NGAP over SCTP), list every Registration Request: time, target AMF, registration
     type, and the 5G-TMSI in its cleartext 5GS mobile identity.
  2. On the radio-link simulation (UERANSIM RLS, UDP 4997), check whether the same 32-bit 5G-TMSI
     appears in the uplink packets the UE sends to each gNB. RRC is UPER-encoded, so the search
     runs at every bit offset.
Output: one CSV row per run, plus a per-run detail file. guti_next_reg is the first registration more than
5 s after the mobility registration (in free5GC AMF-change runs: the initial registration after the #10
reject); guti_periodic is the first periodic registration (type 3) after the move (added 2026-11-10).
Usage: python3 -I summarise_obs.py <runs-dir> <run-name> [...]
"""
import csv, json, subprocess, sys, os

AMF = {"10.100.200.16": "AMF1", "10.100.200.17": "AMF2"}
GNB = {"10.100.200.31": "gNB1", "10.100.200.32": "gNB2"}
UE_IP = "10.100.200.40"


def tshark(run_dir, args):
    cmd = ["docker", "run", "--rm", "-v", f"{os.path.abspath(run_dir)}:/in:ro", "nicolaka/netshoot",
           "tshark", "-r", "/in/obs.pcap"] + args
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def bits(h):
    return bin(int(h, 16))[2:].zfill(len(h) * 4) if h else ""


def main():
    runs_dir = sys.argv[1]
    out = csv.writer(sys.stdout)
    out.writerow(["run", "mode", "n_reg_requests", "guti_at_move", "guti_next_reg", "same_guti",
                  "seen_on_radio_at_move", "seen_on_radio_next_reg",
                  "guti_periodic", "seen_on_radio_periodic"])
    for run in sys.argv[2:]:
        d = os.path.join(runs_dir, run)
        regs = []
        for line in tshark(d, ["-Y", "nas-5gs.mm.message_type == 0x41 && sctp", "-T", "fields",
                               "-E", "occurrence=f", "-e", "frame.time_epoch", "-e", "ip.dst",
                               "-e", "nas-5gs.mm.5gs_reg_type", "-e", "nas-5gs.5g_tmsi",
                               "-e", "nas-5gs.amf_region_id", "-e", "nas-5gs.amf_set_id",
                               "-e", "nas-5gs.amf_pointer"]).splitlines():
            t, dst, rt, tmsi, reg, aset, ptr = (line.split("\t") + [""] * 7)[:7]
            guti = ""
            if tmsi and reg:
                # 5GS mobile identity value after the type octet: PLMN 208/93 (02 f8 39), AMF Region ID,
                # AMF Set ID (10 bits) + AMF Pointer (6 bits), 5G-TMSI: 80 bits in total
                guti = "02f839" + f"{int(reg,0):02x}" + f"{(int(aset,0) << 6) | int(ptr,0):04x}" + f"{int(tmsi,0):08x}"
            regs.append({"t": float(t), "amf": AMF.get(dst, dst), "type": rt, "tmsi": tmsi, "guti": guti})
        rls = []
        for line in tshark(d, ["-Y", "udp.port == 4997", "-T", "fields", "-e", "frame.time_epoch",
                               "-e", "ip.src", "-e", "ip.dst", "-e", "udp.payload"]).splitlines():
            t, src, dst, pl = (line.split("\t") + ["", "", "", ""])[:4]
            if dst in GNB and src not in GNB and pl:   # UE -> gNB uplink (the UE has a dynamic address)
                rls.append((float(t), GNB.get(dst, dst), bits(pl.replace(":", ""))))

        def radio_hits(guti, t0):
            """gNBs on whose uplink the 80-bit 5G-GUTI value appears (any bit offset) within 1 s of the N2 message."""
            if not guti:
                return ""
            pat = bin(int(guti, 16))[2:].zfill(len(guti) * 4)
            return ";".join(sorted({g for (t, g, b) in rls if abs(t - t0) < 1.0 and pat in b}))

        with_tmsi = [r for r in regs if r["guti"]]
        move = next((r for r in with_tmsi if r["type"] == "2"), None)          # mobility registration
        nxt = next((r for r in with_tmsi if move and r["t"] > move["t"] + 5), None)  # next registration
        per = next((r for r in with_tmsi if move and r["type"] == "3" and r["t"] > move["t"]), None)  # periodic
        mode = "control" if "ctl" in run else "amf_change"
        row = [run, mode, len(regs), move["guti"] if move else "", nxt["guti"] if nxt else "",
               (move["guti"] == nxt["guti"]) if (move and nxt) else "",
               radio_hits(move["guti"], move["t"]) if move else "",
               radio_hits(nxt["guti"], nxt["t"]) if nxt else "",
               per["guti"] if per else "", radio_hits(per["guti"], per["t"]) if per else ""]
        out.writerow(row)
        with open(os.path.join(d, "obs_detail.json"), "w") as f:
            json.dump({"registration_requests": regs,
                       "radio_uplink_packets": len(rls)}, f, indent=1)


if __name__ == "__main__":
    main()
