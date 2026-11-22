#!/bin/sh
# GUTI repair test (2026-11-10): does a fresh AMF2 5G-GUTI after the AMF change remove the stale-identifier
# reuse AND the later periodic-registration rejection?
# Three conditions, 10 fresh deployments each, interleaved; radio-link (RLS) + N2 capture through the next
# periodic registration (exp3_observer.sh, T3512 = 30 s at the serving AMF):
#   base: free5GC + #111 fix (ch5/free5gc-amf:fixed), AMF change          -> expected: stale GUTI, #10 at periodic
#   rep : + GUTI repair (ch5/free5gc-amf:fixed-gutirepair), AMF change   -> expected: AMF2 GUTI, periodic accepted
#   ctl : repair image, same-AMF move (gNB2 -> AMF1)                     -> expected: normal path unchanged
set -u
cd "$(dirname "$0")/.."
T=$PWD
F="docker compose -f $T/twoamf/docker-compose.yaml --profile ran --profile ue"
U=UE_IMAGE=ch5/ueransim:patched
for i in 1 2 3 4 5 6 7 8 9 10; do
  env AMF_IMAGE=ch5/free5gc-amf:fixed $U AMF2_CFG=amf2cfg_t3512.yaml sh scripts/exp3_observer.sh gr_base_r$i
  env AMF_IMAGE=ch5/free5gc-amf:fixed-gutirepair $U AMF2_CFG=amf2cfg_t3512.yaml sh scripts/exp3_observer.sh gr_rep_r$i
  env AMF_IMAGE=ch5/free5gc-amf:fixed-gutirepair $U AMF1_CFG=amf1cfg_ctl_t3512.yaml GNB2_CFG=gnb2cfg_ctl.yaml sh scripts/exp3_observer.sh gr_ctl_r$i
done
$F down -v >/dev/null 2>&1
echo GUTIREPAIR_BATCH_DONE
