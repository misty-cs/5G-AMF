#!/bin/sh
# User-plane comparison with UE patch 8 (2026-11-22), interleaved, fresh deployment per run.
#   UE image :patched8 = patches 5, 7 and 8: the mobility registration carries the current ngKSI and, for
#   sessions with uplink data pending since the radio link failure, the Uplink data status IE.
#   change_p8 : AMF change (gNB2 -> AMF2).
#   ctlmob_p8 : same AMF with a mobility registration (amf1_ctlmob.yaml, gNB2 -> AMF1).
# traffic_pilot_ctlmob_p8a used an earlier version of patch 8 and is not part of this batch.
cd "$(dirname "$0")/.."
for i in 1 2 3 4 5; do
  UE_IMAGE=ch5/ueransim:patched8 sh scripts/run_pdu_traffic.sh traffic_change_p8_r$i change
  UE_IMAGE=ch5/ueransim:patched8 sh scripts/run_pdu_traffic.sh traffic_ctlmob_p8_r$i ctlmob
done
docker compose --profile ran --profile ue down -v >/dev/null 2>&1
echo BATCH_DONE
