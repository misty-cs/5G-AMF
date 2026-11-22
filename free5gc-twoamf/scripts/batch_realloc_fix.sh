#!/bin/sh
# Repeat runs for the patched slice-triggered re-allocation (experiment 5).
set -u
cd "$(dirname "$0")/.."
for i in 1 2 3 4 5; do
  env AMF_IMAGE=ch5/free5gc-amf:fixed-trace-realloc UE_IMAGE=ch5/ueransim:patched6 \
      AMF1_CFG=amf1cfg_sliceA.yaml AMF2_CFG=amf2cfg_sliceAB.yaml GNB1_CFG=gnb1cfg_both_rev.yaml \
      sh scripts/realloc_once.sh exp5fresh_r$i; echo "$(date -u +%T) exp5fresh_r$i done"
  sh scripts/exp5_slice_trigger.sh exp5reg_r$i >/dev/null 2>&1; echo "$(date -u +%T) exp5reg_r$i done"
done
docker compose --profile ran --profile ue --profile pdu down -v >/dev/null 2>&1
echo "batch complete"
