#!/bin/sh
# Clean reproduction batch (Chapter 5 next experiment, part 1 and 3).
# Round-robin over configurations so time-of-run effects spread evenly.
# Usage: sh scripts/batch_repro.sh <N>   (logs to repro_batch.log)
set -u
cd "$(dirname "$0")/.."
T=$PWD; N=${1:-10}
F="docker compose -f $T/twoamf/docker-compose.yaml --profile ran --profile ue"
O="docker compose -f $T/open5gs-twoamf/docker-compose.yaml --profile ran --profile ue"
run_f() { # name, then env assignments
  name=$1; shift
  $O down -v >/dev/null 2>&1
  env "$@" sh "$T/twoamf/scripts/run_exp1.sh" "$name" >/dev/null 2>&1
  echo "$(date -u +%T) $name done"
}
run_o() {
  $F down -v >/dev/null 2>&1; docker rm -f cap >/dev/null 2>&1
  sh "$T/open5gs-twoamf/scripts/run_exp1.sh" "$1" >/dev/null 2>&1
  echo "$(date -u +%T) $1 done"
}
U=UE_IMAGE=ch5/ueransim:patched
for i in $(seq 1 "$N"); do
  run_f repro_f5unmod_r$i  AMF_IMAGE=ch5/free5gc-amf:main $U
  run_f repro_f5fix_r$i    AMF_IMAGE=ch5/free5gc-amf:fixed $U
  if [ $((i % 2)) -eq 0 ]; then
    run_f repro_f5fixnea2_r$i AMF_IMAGE=ch5/free5gc-amf:fixed $U AMF1_CFG=amf1cfg_nea2.yaml AMF2_CFG=amf2cfg_nea2.yaml
  fi
  run_f repro_f5ctl_r$i    AMF_IMAGE=ch5/free5gc-amf:main $U AMF1_CFG=amf1cfg_ctl.yaml GNB2_CFG=gnb2cfg_ctl.yaml
  if [ "$i" -le 5 ]; then
    run_f repro_f5ueorig_r$i AMF_IMAGE=ch5/free5gc-amf:main UE_IMAGE=free5gc/ueransim:latest
  fi
  run_o repro_o5_r$i
done
$F down -v >/dev/null 2>&1; $O down -v >/dev/null 2>&1
echo "$(date -u +%T) batch complete"
