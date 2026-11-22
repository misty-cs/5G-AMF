#!/bin/sh
# Experiment 1 on Open5GS: registration with AMF change (gNB1/AMF1 -> gNB2/AMF2).
# Usage: sh scripts/run_exp1.sh <run-name>
set -u
cd "$(dirname "$0")/.."
R=runs/${1:?run name}; mkdir -p "$R"
echo "UE_IMAGE=${UE_IMAGE:-ch5/ueransim:patched} O5_AMF2_CFG=${O5_AMF2_CFG:-amf2.yaml} POST_WAIT=${POST_WAIT:-30}" > "$R/00_meta.txt"; date -u +%FT%TZ >> "$R/00_meta.txt"
docker rm -f o5-cap >/dev/null 2>&1
docker compose --profile ran --profile ue down -v >/dev/null 2>&1
docker compose up -d >/dev/null 2>&1; sleep 10
docker exec -i o5-mongodb mongo --quiet open5gs < scripts/provision.js >> "$R/00_meta.txt"
docker restart o5-udr o5-pcf >/dev/null; sleep 4; docker restart o5-upf >/dev/null; sleep 2; docker restart o5-smf o5-amf1 o5-amf2 >/dev/null; sleep 6
docker run -d --name o5-cap --net host -v "$PWD/$R":/out nicolaka/netshoot \
  tcpdump -i br-o5 -s 0 -w /out/sbi.pcap 'tcp port 7777 or sctp' >/dev/null; sleep 2
docker compose --profile ran up -d gnb1 >/dev/null 2>&1; sleep 3
docker compose --profile ue up -d ue >/dev/null 2>&1; sleep 10
docker compose --profile ran up -d gnb2 >/dev/null 2>&1; sleep 4
docker stop o5-gnb1 >/dev/null; sleep ${POST_WAIT:-30}
sleep 1; docker stop o5-cap >/dev/null; docker rm o5-cap >/dev/null
for c in amf1 amf2 ue gnb2 udm pcf smf upf; do docker logs o5-$c 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$R/$c.log"; done
grep -E "Registration|successful|failed" "$R/ue.log" | tail -8
