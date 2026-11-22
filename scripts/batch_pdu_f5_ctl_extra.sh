#!/bin/sh
# Two more free5GC PDU-session control runs (no AMF change), bringing the control to 5 runs.
set -u
cd "$(dirname "$0")/.."
U="UE_IMAGE=ch5/ueransim:patched PDU=1 UE_CFG=uecfg_pdu.yaml AMF_IMAGE=ch5/free5gc-amf:fixed-trace"
for i in 4 5; do
  env $U AMF1_CFG=amf1cfg_ctl.yaml GNB2_CFG=gnb2cfg_ctl.yaml sh twoamf/scripts/run_exp1.sh pdu_f5ctl_r$i >/dev/null 2>&1; echo "pdu_f5ctl_r$i done"
done
docker compose -f twoamf/docker-compose.yaml --profile ran --profile ue --profile pdu down -v >/dev/null 2>&1
echo PDU_CTL_DONE
