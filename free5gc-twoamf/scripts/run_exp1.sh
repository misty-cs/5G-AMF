#!/bin/sh
# Experiment 1: registration with AMF change (idle mobility gNB1/AMF1 -> gNB2/AMF2).
# Usage: UE_IMAGE=ch5/ueransim:patched sh scripts/run_exp1.sh <run-name>
set -u
cd "$(dirname "$0")/.." && docker compose config -q || { echo "compose config invalid"; exit 1; }
R=runs/${1:?run name}; mkdir -p "$R"
export UE_IMAGE=${UE_IMAGE:-free5gc/ueransim:latest}
echo "UE_IMAGE=$UE_IMAGE AMF_IMAGE=${AMF_IMAGE:-free5gc/amf:v4.3.0} AMF2_CFG=${AMF2_CFG:-amf2cfg.yaml} AMF1_CFG=${AMF1_CFG:-amf1cfg.yaml} GNB2_CFG=${GNB2_CFG:-gnb2cfg.yaml} SUBSCRIBER=${SUBSCRIBER:-subscriber.json} POST_WAIT=${POST_WAIT:-25} PDU=${PDU:-} UE_CFG=${UE_CFG:-uecfg.yaml}" > "$R/00_meta.txt"; date -u +%FT%TZ >> "$R/00_meta.txt"
pc() { docker exec probe curl -s --http2-prior-knowledge -w ' HTTP %{http_code}\n' "$@"; }
PATCH='[{"op":"replace","path":"/expiry","value":"2027-01-01T00:00:00Z"}]'

# 1. clean core
docker rm -f cap >/dev/null 2>&1
docker compose --profile ran --profile ue --profile pdu down -v >/dev/null 2>&1
docker compose ${PDU:+--profile pdu} up -d >/dev/null 2>&1; sleep 15
sh scripts/provision.sh >> "$R/00_meta.txt"
docker run -d --name cap --net host -v "$PWD/$R":/out nicolaka/netshoot \
  tcpdump -i br-twoamf -s 0 -w /out/sbi.pcap 'tcp port 8000 or tcp port 9000 or sctp' >/dev/null
[ "${OBS_CAP:-}" = 1 ] && docker run -d --name obs --net host -v "$PWD/$R":/out nicolaka/netshoot \
  tcpdump -i br-twoamf -s 0 -w /out/obs.pcap 'udp port 4997 or sctp' >/dev/null  # radio-link (RLS) + N2 capture; stopped by the caller
docker exec -d probe sh -c 'rm -f /tmp/notify.log; while true; do printf "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n" | nc -l -p 9000 >> /tmp/notify.log 2>&1; echo "---conn-end" >> /tmp/notify.log; done'
sleep 2

# 2. register at AMF1, subscribe
docker compose --profile ran --profile ue up -d gnb1 >/dev/null 2>&1; sleep 3
docker compose --profile ue up -d ue >/dev/null 2>&1; sleep 8
BODY='{"subscription":{"eventList":[{"type":"LOCATION_REPORT","immediateFlag":false},{"type":"REACHABILITY_REPORT","immediateFlag":false}],"eventNotifyUri":"http://probe.free5gc.org:9000/notify","notifyCorrelationId":"ch5-exp1","nfId":"11111111-2222-3333-4444-555555555555","supi":"imsi-208930000000001"}}'
pc -X POST http://amf1.free5gc.org:8000/namf-evts/v1/subscriptions -H 'Content-Type: application/json' -d "$BODY" > "$R/01_create_sub_amf1.txt"
pc -X PATCH http://amf1.free5gc.org:8000/namf-evts/v1/subscriptions/1 -H 'Content-Type: application/json' -d "$PATCH" > "$R/02_patch_sub1_amf1_before.txt"

# 3. move the UE
docker compose --profile ran up -d gnb2 >/dev/null 2>&1; sleep 4
docker stop gnb1 >/dev/null; sleep ${POST_WAIT:-25}

# 4. probe
{ for a in amf1 amf2; do
    echo "== $a OAM"; docker exec probe curl -s http://$a.free5gc.org:8000/namf-oam/v1/registered-ue-context; echo
    echo "== $a PATCH sub 1"; pc -X PATCH http://$a.free5gc.org:8000/namf-evts/v1/subscriptions/1 -H 'Content-Type: application/json' -d "$PATCH"
  done
  echo "== notify sink bytes"; docker exec probe sh -c 'wc -c < /tmp/notify.log'
} > "$R/03_after_move_state.txt"
docker exec probe cat /tmp/notify.log > "$R/notify.raw" 2>/dev/null
sleep 1; docker stop cap >/dev/null; docker rm cap >/dev/null
for c in amf1 amf2 ue gnb1 gnb2 udm pcf ${PDU:+smf upf}; do docker logs $c 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$R/$c.log"; done
cat "$R/03_after_move_state.txt"
