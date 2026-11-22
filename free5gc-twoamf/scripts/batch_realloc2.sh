#!/bin/sh
# Experiment 5 at patch level realloc2 (TS 23.502 4.2.2.2.3 step 7(A)/8 fixes); see PATCHES.md.
set -u
cd "$(dirname "$0")/.."
for i in 1 2 3 4 5; do
  env AMF_IMAGE=ch5/free5gc-amf:fixed-trace-realloc2 SUBSCRIBER=subscriber_rich.json \
      sh scripts/exp5_slice_trigger.sh exp5r2reg_r$i >/dev/null 2>&1; echo "$(date -u +%T) exp5r2reg_r$i done"
  env AMF_IMAGE=ch5/free5gc-amf:fixed-trace-realloc2 UE_IMAGE=ch5/ueransim:patched6 \
      AMF1_CFG=amf1cfg_sliceA.yaml AMF2_CFG=amf2cfg_sliceAB.yaml GNB1_CFG=gnb1cfg_both_rev.yaml \
      sh scripts/realloc_once.sh exp5r2fresh_r$i; echo "$(date -u +%T) exp5r2fresh_r$i done"
done
docker compose --profile ran --profile ue --profile pdu down -v >/dev/null 2>&1
echo "batch complete"
