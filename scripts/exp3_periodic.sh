#!/bin/sh
# Experiment 3: consequence of the kept 5G-GUTI at the UE's next registration.
# Runs exp1 (move to the second AMF), releases the UE to CM-IDLE at the serving gNB,
# and waits for the periodic registration (T3512 = 30 s in the *_t3512 configs).
# Usage: [env ...] sh scripts/exp3_periodic.sh f5|o5 <run-name>
set -u
cd "$(dirname "$0")/.."
T=$PWD; core=$1; name=$2
if [ "$core" = f5 ]; then
  POST_WAIT=20 sh twoamf/scripts/run_exp1.sh "$name" >/dev/null 2>&1
  R=twoamf/runs/$name; G=gnb2; P=""
else
  POST_WAIT=20 sh open5gs-twoamf/scripts/run_exp1.sh "$name" >/dev/null 2>&1
  R=open5gs-twoamf/runs/$name; G=o5-gnb2; P=o5-
fi
N=$(docker exec $G ./nr-cli --dump | head -1)
date -u +"%Y-%m-%d %H:%M:%S" > "$R/10_release_time.txt"
for id in $(docker exec $G ./nr-cli "$N" -e ue-list | sed -n 's/^- ue-id: //p'); do
  docker exec $G ./nr-cli "$N" -e "ue-release $id" >> "$R/10_release_time.txt" 2>&1
done
sleep 75
for c in ue amf1 amf2; do docker logs ${P}$c 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$R/${c}_after.log"; done
echo "$name done"
