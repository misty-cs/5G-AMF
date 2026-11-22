#!/bin/sh
# 5 AMF-change (free5GC + #111 fix) + 5 same-AMF control runs, interleaved, with radio-link capture.
set -u
cd "$(dirname "$0")/.."
T=$PWD
F="docker compose -f $T/twoamf/docker-compose.yaml --profile ran --profile ue"
U=UE_IMAGE=ch5/ueransim:patched
for i in 1 2 3 4 5; do
  env AMF_IMAGE=ch5/free5gc-amf:fixed $U AMF2_CFG=amf2cfg_t3512.yaml sh scripts/exp3_observer.sh obs_f5fix_r$i
  env AMF_IMAGE=ch5/free5gc-amf:fixed $U AMF1_CFG=amf1cfg_ctl_t3512.yaml GNB2_CFG=gnb2cfg_ctl.yaml sh scripts/exp3_observer.sh obs_f5ctl_r$i
done
$F down -v >/dev/null 2>&1
echo OBS_BATCH_DONE
