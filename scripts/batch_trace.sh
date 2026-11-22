#!/bin/sh
# State-use trace batch (Chapter 5 next experiment, part 2), free5GC with trace instrumentation.
set -u
cd "$(dirname "$0")/.."
T=$PWD
docker compose -f $T/open5gs-twoamf/docker-compose.yaml --profile ran --profile ue down -v >/dev/null 2>&1
U=UE_IMAGE=ch5/ueransim:patched
r() { name=$1; shift; env "$@" sh "$T/twoamf/scripts/run_exp1.sh" "$name" >/dev/null 2>&1; echo "$(date -u +%T) $name done"; }
for i in 1 2 3 4 5; do
  r trace_fix_default_r$i AMF_IMAGE=ch5/free5gc-amf:fixed-trace $U
  r trace_fix_rich_r$i    AMF_IMAGE=ch5/free5gc-amf:fixed-trace $U SUBSCRIBER=subscriber_rich.json
  if [ "$i" -le 3 ]; then
    r trace_ctl_rich_r$i   AMF_IMAGE=ch5/free5gc-amf:main-trace $U SUBSCRIBER=subscriber_rich.json AMF1_CFG=amf1cfg_ctl.yaml GNB2_CFG=gnb2cfg_ctl.yaml
    r trace_unmod_rich_r$i AMF_IMAGE=ch5/free5gc-amf:main-trace $U SUBSCRIBER=subscriber_rich.json
  fi
done
docker compose -f $T/twoamf/docker-compose.yaml --profile ran --profile ue down -v >/dev/null 2>&1
echo "$(date -u +%T) trace batch complete"
