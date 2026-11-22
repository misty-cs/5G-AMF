#!/bin/sh
# Finding 2, consumer side: 5 AMF-change (free5GC + #111 fix) + 5 same-AMF control runs, interleaved.
# Same AMF image in both modes; the fix touches only the transfer path.
set -u
cd "$(dirname "$0")/.."
T=$PWD
U=UE_IMAGE=ch5/ueransim:patched
I=AMF_IMAGE=ch5/free5gc-amf:fixed
for i in 1 2 3 4 5; do
  env $I $U sh twoamf/scripts/run_exp2_notify.sh notify_change_r$i >/dev/null 2>&1; echo "$(date -u +%T) notify_change_r$i done"
  env $I $U AMF1_CFG=amf1cfg_ctl.yaml GNB2_CFG=gnb2cfg_ctl.yaml sh twoamf/scripts/run_exp2_notify.sh notify_ctl_r$i >/dev/null 2>&1; echo "$(date -u +%T) notify_ctl_r$i done"
done
docker compose -f $T/twoamf/docker-compose.yaml --profile ran --profile ue down -v >/dev/null 2>&1
echo NOTIFY_BATCH_DONE
