#!/bin/sh
# 5 AMF-change + 5 control runs, interleaved (change, control, change, ...).
cd "$(dirname "$0")/.."
for i in 1 2 3 4 5; do
  sh scripts/run_pdu_traffic.sh traffic_change_r$i change
  sh scripts/run_pdu_traffic.sh traffic_control_r$i control
done
docker compose --profile ran --profile ue down -v >/dev/null 2>&1
echo BATCH_DONE
