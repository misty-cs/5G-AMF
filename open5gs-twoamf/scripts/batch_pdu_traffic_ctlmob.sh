#!/bin/sh
# Same-AMF control WITH a mobility registration (2026-11-22), interleaved, fresh deployment per run.
#   ctlmob    : AMF1 serves TAC 1 and TAC 2 as two registration areas (amf1_ctlmob.yaml), so the move
#               gNB1 -> gNB2 triggers a mobility registration at the same AMF. UE image :patched5.
#   *_p7      : the same with UE patch 7 (mobility registration carries the current ngKSI), :patched7.
#   change_p7 : AMF change with UE patch 7.
# traffic_ctlmob_r1 and traffic_ctlmob_p7_r1 were run first as pilots with the same settings.
cd "$(dirname "$0")/.."
for i in 1 2 3 4 5; do
  UE_IMAGE=ch5/ueransim:patched7 sh scripts/run_pdu_traffic.sh traffic_change_p7_r$i change
  if [ "$i" -ge 2 ]; then UE_IMAGE=ch5/ueransim:patched7 sh scripts/run_pdu_traffic.sh traffic_ctlmob_p7_r$i ctlmob; fi
  if [ "$i" -ge 2 ]; then UE_IMAGE=ch5/ueransim:patched5 sh scripts/run_pdu_traffic.sh traffic_ctlmob_r$i ctlmob; fi
done
docker compose --profile ran --profile ue down -v >/dev/null 2>&1
echo BATCH_DONE
