"""For each run: count UE->gNB RLS uplink packets that contain the old AMF1 GUTI (full 80 bits) or its
48-bit 5G-S-TMSI, in three windows: before the move, during the move (up to 2 s after the last
registration that still carries the old GUTI before the periodic one), and after it."""
import json, os, subprocess, sys
RUNS = sys.argv[1]
GNB = {"10.100.200.31": "gNB1", "10.100.200.32": "gNB2"}
OLD_GUTI = "02f839cafe0000000001"
OLD_STMSI = "fe0000000001"          # AMF Set ID + Pointer (16 bits) + 5G-TMSI
def bits(h): return bin(int(h, 16))[2:].zfill(len(h) * 4) if h else ""
PG, PS = bits(OLD_GUTI), bits(OLD_STMSI)
print("run,move_t,last_old_reg_t,periodic_t,guti_before,guti_during,guti_after,stmsi_during,stmsi_after")
for run in sys.argv[2:]:
    d = os.path.join(RUNS, run)
    regs = json.load(open(f"{d}/obs_detail.json"))["registration_requests"]
    move = next(r for r in regs if r["type"] == "2")
    per = next((r for r in regs if r["type"] == "3" and r["t"] > move["t"]), None)
    pre = [r for r in regs if r["t"] >= move["t"] and (per is None or r["t"] < per["t"])]
    end = max(r["t"] for r in pre) + 2.0
    out = subprocess.run(["docker", "run", "--rm", "-v", f"{os.path.abspath(d)}:/in:ro", "nicolaka/netshoot",
                          "tshark", "-r", "/in/obs.pcap", "-Y", "udp.port == 4997", "-T", "fields",
                          "-e", "frame.time_epoch", "-e", "ip.src", "-e", "ip.dst", "-e", "udp.payload"],
                         capture_output=True, text=True).stdout
    c = {k: 0 for k in ["gb", "gd", "ga", "sd", "sa"]}
    for line in out.splitlines():
        t, src, dst, pl = (line.split("\t") + [""] * 4)[:4]
        if dst not in GNB or src in GNB or not pl: continue
        t, b = float(t), bits(pl.replace(":", ""))
        w = "b" if t < move["t"] - 1 else ("d" if t <= end else "a")
        if PG in b: c["g" + w] += 1
        if PS in b and w != "b": c["s" + w] += 1
    t0 = regs[0]["t"]
    print(f'{run},{move["t"]-t0:.1f},{end-2-t0:.1f},{(per["t"]-t0) if per else -1:.1f},{c["gb"]},{c["gd"]},{c["ga"]},{c["sd"]},{c["sa"]}')
