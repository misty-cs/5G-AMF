#!/bin/sh
# Unpatched baseline for slice re-allocation: replaces the invalid realloc_r1-3 (see runs_invalid/README.md).
# Same setup as the original test: AMF1 = slice A only, AMF2 = slice B only, gNB1 -> both, stock UERANSIM,
# free5GC AMF with only the #111 fix + logging trace (no re-allocation patches).
set -u
cd "$(dirname "$0")/.."
for i in 1 2 3 4 5; do
  env AMF_IMAGE=ch5/free5gc-amf:fixed-trace UE_IMAGE=free5gc/ueransim:latest \
      AMF1_CFG=amf1cfg_sliceA.yaml AMF2_CFG=amf2cfg_sliceB.yaml GNB1_CFG=gnb1cfg_both.yaml \
      sh scripts/realloc_once.sh realloc_base_r$i; echo "$(date -u +%T) realloc_base_r$i done"
done
docker compose --profile ran --profile ue --profile pdu down -v >/dev/null 2>&1
echo "batch complete"
