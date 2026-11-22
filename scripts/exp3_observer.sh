#!/bin/sh
# Observer variant of Experiment 3 (free5GC): same steps as exp3_periodic.sh (f5), plus a capture of the
# UE-gNB radio-link simulation (RLS, UDP 4997) and N2 (SCTP) for the whole run, including the periodic
# registration. Usage: [env ...] sh scripts/exp3_observer.sh <run-name>
set -u
cd "$(dirname "$0")/.."
name=$1; docker rm -f obs >/dev/null 2>&1
OBS_CAP=1 POST_WAIT=20 sh twoamf/scripts/run_exp1.sh "$name" >/dev/null 2>&1
R=twoamf/runs/$name; G=gnb2
N=$(docker exec $G ./nr-cli --dump | head -1)
date -u +"%Y-%m-%d %H:%M:%S" > "$R/10_release_time.txt"
for id in $(docker exec $G ./nr-cli "$N" -e ue-list | sed -n 's/^- ue-id: //p'); do
  docker exec $G ./nr-cli "$N" -e "ue-release $id" >> "$R/10_release_time.txt" 2>&1
done
sleep 75
docker stop obs >/dev/null 2>&1; docker rm obs >/dev/null 2>&1
for c in ue amf1 amf2; do docker logs $c 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$R/${c}_after.log"; done
docker inspect -f '{{.Name}} {{.State.StartedAt}}' amf1 amf2 ue gnb2 >> "$R/00_meta.txt" 2>/dev/null
echo "$name done"
