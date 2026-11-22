#!/bin/sh
set -u
cd "$(dirname "$0")/.."
T=$PWD
F="docker compose -f $T/twoamf/docker-compose.yaml --profile ran --profile ue"
O="docker compose -f $T/open5gs-twoamf/docker-compose.yaml --profile ran --profile ue"
U=UE_IMAGE=ch5/ueransim:patched
for i in 1 2 3 4 5; do
  $O down -v >/dev/null 2>&1
  env AMF_IMAGE=ch5/free5gc-amf:fixed $U AMF2_CFG=amf2cfg_t3512.yaml sh scripts/exp3_periodic.sh f5 exp3_f5fix_r$i
  env AMF_IMAGE=ch5/free5gc-amf:fixed $U AMF1_CFG=amf1cfg_ctl_t3512.yaml GNB2_CFG=gnb2cfg_ctl.yaml sh scripts/exp3_periodic.sh f5 exp3_f5ctl_r$i
  $F down -v >/dev/null 2>&1; docker rm -f cap >/dev/null 2>&1
  env O5_AMF2_CFG=amf2_t3512.yaml sh scripts/exp3_periodic.sh o5 exp3_o5_r$i
  $O down -v >/dev/null 2>&1
done
$F down -v >/dev/null 2>&1; $O down -v >/dev/null 2>&1
echo "exp3 batch complete"
