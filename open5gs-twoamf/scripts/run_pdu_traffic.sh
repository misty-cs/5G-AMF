#!/bin/sh
# User-plane test across a move (Open5GS). Continuous ping from the UE through its PDU session
# to the UPF gateway (10.45.0.1) while the UE moves gNB1 -> gNB2.
# Usage: sh scripts/run_pdu_traffic.sh <run-name> <change|control>
#   change : gNB2 -> AMF2 (different AMF set)  => registration with AMF change
#   control: gNB2 -> AMF1 (AMF1 serves TAC 1 and 2) => no AMF change
#   ctlmob : gNB2 -> AMF1, TAC 1 and 2 in separate registration areas => mobility registration, no AMF change
set -u
cd "$(dirname "$0")/.."
RUN=${1:?run name}; MODE=${2:?change|control}
R=runs/$RUN; mkdir -p "$R"
export UE_IMAGE=${UE_IMAGE:-ch5/ueransim:patched5}   # patched UE (1-4) + rt_tables fix so the TUN comes up
export O5_UE_CFG=ue_pdu.yaml
if [ "$MODE" = control ]; then export O5_AMF1_CFG=amf1_ctl.yaml O5_GNB2_CFG=gnb2_ctl.yaml;
elif [ "$MODE" = ctlmob ]; then export O5_AMF1_CFG=amf1_ctlmob.yaml O5_GNB2_CFG=gnb2_ctl.yaml; else export O5_AMF1_CFG=amf1.yaml O5_GNB2_CFG=gnb2.yaml; fi
{ echo "MODE=$MODE UE_IMAGE=$UE_IMAGE O5_AMF1_CFG=$O5_AMF1_CFG O5_GNB2_CFG=$O5_GNB2_CFG"; date -u +%FT%TZ; } > "$R/00_meta.txt"
docker rm -f o5-cap >/dev/null 2>&1
docker compose --profile ran --profile ue down -v >/dev/null 2>&1
docker compose up -d >/dev/null 2>&1; sleep 10
docker exec -i o5-mongodb mongo --quiet open5gs < scripts/provision.js >> "$R/00_meta.txt"
docker restart o5-udr o5-pcf >/dev/null; sleep 4; docker restart o5-upf >/dev/null; sleep 2; docker restart o5-smf o5-amf1 o5-amf2 >/dev/null; sleep 6
docker run -d --name o5-cap --net host -v "$PWD/$R":/out nicolaka/netshoot \
  tcpdump -i br-o5 -s 0 -w /out/cap.pcap 'tcp port 7777 or sctp or udp port 2152' >/dev/null; sleep 2
docker compose --profile ran up -d gnb1 >/dev/null 2>&1; sleep 3
docker compose --profile ue up -d ue >/dev/null 2>&1
for i in $(seq 1 30); do docker exec o5-ue ip -4 addr show uesimtun0 >/dev/null 2>&1 && break; sleep 1; done
docker exec o5-ue ip -4 addr show uesimtun0 > "$R/tun_before.txt" 2>&1
docker exec -d o5-ue sh -c 'ping -I uesimtun0 -i 0.2 -D -O -w 50 10.45.0.1 > /tmp/ping.log 2>&1'
sleep 6
docker compose --profile ran up -d gnb2 >/dev/null 2>&1; sleep 4
date -u +%s.%N > "$R/t_move.txt"; docker stop o5-gnb1 >/dev/null
sleep 40
docker exec o5-ue cat /tmp/ping.log > "$R/ping.log" 2>&1
docker exec o5-ue ip -4 addr show uesimtun0 > "$R/tun_after.txt" 2>&1
sleep 1; docker stop o5-cap >/dev/null; docker rm o5-cap >/dev/null
for c in amf1 amf2 ue gnb2 smf upf; do docker logs o5-$c 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$R/$c.log"; done
docker inspect -f '{{.Name}} {{.State.StartedAt}}' o5-amf1 o5-amf2 o5-smf o5-upf o5-ue >> "$R/00_meta.txt"
echo "$RUN $MODE: $(grep -c 'bytes from' "$R/ping.log") replies"
