# What Survives an AMF Change? Artifact

This artifact contains the testbed, local patches, run scripts, per-run logs and captures, and summary tables for the NetSoft 2027 paper "What Survives an AMF Change? Measuring Per-UE State Continuity in Open-Source 5G Cores."

## Layout

| Path | Contents |
|---|---|
| `free5gc-twoamf/` | Two-AMF free5GC testbed: `docker-compose.yaml`, NF configs, run scripts |
| `free5gc-twoamf/amf-patched/` | Dockerfile that builds the free5GC AMF from `free5gc/amf` @ `b626080`, plus the local patches and the logging-only state trace (`ch5_trace.go`) |
| `free5gc-twoamf/ueransim-patched/` | Dockerfile that builds UERANSIM @ `4f45e18` with the four UE conformance patches (Table III) |
| `free5gc-twoamf/runs/` | One folder per run: NF logs, `cap.pcap` (N2 and SBI), metadata with container start times |
| `open5gs-twoamf/` | Two-AMF Open5GS testbed (Open5GS @ `3e007dd`, built by `image/Dockerfile`), configs, run scripts, runs |
| `scripts/` | Batch drivers (`batch_*.sh`) and summarisers (`summarise_*`) |
| `results/` | Per-run CSV tables produced by the summarisers |
| `PATCHES.md` | Every local patch: what it changes, its 3GPP basis, the image tag that contains it, and which runs used it |

## Requirements

- Docker with Compose v2. The runs used Colima on Apple silicon (4 vCPU, 6 GB), arm64 images.
- free5GC session tests (Experiment 4) need the `gtp5g` v0.9.14 kernel module in the Docker VM. No other test needs it.

## Building the images

Build commands are listed at the top of `free5gc-twoamf/amf-patched/Dockerfile`, for example:

```sh
cd free5gc-twoamf/amf-patched
docker build --build-arg APPLY_FIX=0 -t ch5/free5gc-amf:main .
docker build --build-arg APPLY_FIX=1 -t ch5/free5gc-amf:fixed .
docker build --build-arg APPLY_FIX=1 --build-arg TRACE=1 -t ch5/free5gc-amf:fixed-trace .
docker build --build-arg APPLY_FIX=0 --build-arg TRACE=1 -t ch5/free5gc-amf:main-trace .
docker build --build-arg APPLY_FIX=1 --build-arg GUTI_REPAIR=1 -t ch5/free5gc-amf:fixed-gutirepair .
```

Then:
- `free5gc-twoamf/ueransim-patched/Dockerfile` builds `ch5/ueransim:patched` (UE patches 1–4). The current Dockerfile also includes the TUN fix the user-plane tests need.
- The session tests used the tag `:patched5`, built with `PATCH5=1`. This adds gNB patch 5, which these tests never trigger.
- The Experiment 4 controls with UE patch 7 used `:patched7`, built with `PATCH5=1 PATCH7=1`. With this patch the mobility registration carries the current ngKSI. The paper's Table III calls it patch 5.
- The Experiment 4 user-plane comparison with UE patch 8 used `:patched8`, built with `PATCH5=1 PATCH7=1 PATCH8=1`. With this patch, uplink data that arrives during cell search is kept pending and the mobility registration carries the Uplink data status IE. The paper's Table III lists patches 7 and 8 together as patch 5.
- `open5gs-twoamf/image/Dockerfile` builds `ch5/open5gs:3e007dd`.
- The other free5GC network functions use the public v4.3.0 images.

## Reproducing each result

Run batch drivers from the artifact root. Every run starts from a fresh deployment, and configurations are interleaved.

| Paper result | Batch driver | Summariser | Output |
|---|---|---|---|
| Table IV, Experiment 1 (registration across an AMF change) | `scripts/batch_repro.sh` | `scripts/summarise_batch.py` | `results/repro_runs.csv` |
| Table V, Experiment 2 (per-field state, free5GC) | `scripts/batch_trace.sh`, `scripts/batch_trace_extra.sh` | `scripts/summarise_trace.py` | `results/trace_fields.csv` |
| Table V, Open5GS column | Open5GS runs `repro_o5_*`, `exp3_o5_*`, `pdu_o5_*`, `traffic_change_*` | AMF2 debug log (`amf2.log`: transfer body, UDM and PCF exchanges) | — |
| Finding 2, subscriber view | `scripts/batch_exp2_notify.sh` | `scripts/summarise_notify.py` | `results/notify_runs.csv` |
| Table VI, Experiment 3 (periodic registration after the move) | `scripts/batch_exp3.sh` | `scripts/summarise_exp3.py` | `results/exp3_runs.csv` |
| Finding 3b, identity on the simulated radio link | `scripts/batch_exp3_obs.sh` | `scripts/summarise_obs.py` | `results/obs_runs.csv` |
| GUTI repair test | `scripts/batch_gutirepair.sh` | `scripts/summarise_gutirepair.py`, `scripts/scan_old_guti.py` | `results/gutirepair_runs.csv`, `results/gutirepair_oldguti_scan.csv` |
| Table VII, Experiment 4 (free5GC) | `scripts/batch_pdu_f5.sh`, `scripts/batch_pdu_f5_ctl_extra.sh` | `scripts/summarise_pdu_f5.sh` | `results/pdu_f5_runs.csv` |
| Table VII, Experiment 4 (Open5GS, user plane) | `open5gs-twoamf/scripts/batch_pdu_traffic.sh` | `open5gs-twoamf/scripts/summarise_pdu_traffic.py` | `open5gs-twoamf/pdu_traffic_runs.csv` |
| Experiment 4 (Open5GS, session state) | runs `pdu_o5_*` | `scripts/summarise_pdu_o5.sh` | `results/pdu_o5_runs.csv` |
| Experiment 4 (Open5GS, same-AMF control with a mobility registration; UE patch 7) | `open5gs-twoamf/scripts/batch_pdu_traffic_ctlmob.sh` | `open5gs-twoamf/scripts/summarise_pdu_traffic.py` | `open5gs-twoamf/pdu_traffic_ctlmob_runs.csv` |
| Experiment 4 (Open5GS, user plane after a mobility registration; UE patch 8) | `open5gs-twoamf/scripts/batch_pdu_traffic_p8.sh` | `open5gs-twoamf/scripts/summarise_pdu_traffic.py` | `open5gs-twoamf/pdu_traffic_p8_runs.csv` |

Folders and scripts named `realloc*` or `exp5*` belong to an AMF re-allocation study that is not reported in this paper.

## Notes

- **Patched runs are reported separately.** Every finding measured on a patched build is reported as such (see `PATCHES.md`). The free5GC AMF patches enable behaviour that the specification requires (the #111 fix) or test a repair (GUTI repair). The trace adds logging only.
- **Test data only.** Key material in the logs belongs to the test subscriber provisioned by the run scripts. The state trace hashes key material.
- **Run validity.** Runs that failed the fresh-deployment check were excluded from this artifact.
