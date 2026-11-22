#!/bin/sh
# One slice-triggered re-allocation run. Usage: [env] sh scripts/realloc_once.sh <run-name>
set -u
cd "$(dirname "$0")/.."
R=runs/$1; rm -rf $R; mkdir -p $R
echo "AMF_IMAGE=$AMF_IMAGE UE_IMAGE=$UE_IMAGE AMF1_CFG=$AMF1_CFG AMF2_CFG=$AMF2_CFG GNB1_CFG=$GNB1_CFG" > $R/00_meta.txt
docker rm -f cap >/dev/null 2>&1
docker compose --profile ran --profile ue --profile pdu down -v >/dev/null 2>&1; docker compose up -d >/dev/null 2>&1; sleep 15
sh scripts/provision.sh >/dev/null 2>&1
docker run -d --name cap --net host -v "$PWD/$R":/out nicolaka/netshoot tcpdump -i br-twoamf -s 0 -w /out/sbi.pcap 'tcp port 8000 or sctp' >/dev/null 2>&1; sleep 2
docker compose --profile ran up -d gnb1 >/dev/null 2>&1; sleep 4; docker compose --profile ue up -d ue >/dev/null 2>&1; sleep ${WAIT:-14}
docker stop cap >/dev/null 2>&1; docker rm cap >/dev/null 2>&1
for c in amf1 amf2 ue gnb1 udm; do docker logs $c > $R/$c.log 2>&1; perl -i -pe 's/\x1b\[[0-9;]*m//g' $R/$c.log; done
