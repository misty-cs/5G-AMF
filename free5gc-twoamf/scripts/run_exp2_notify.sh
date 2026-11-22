#!/bin/sh
# Finding 2, consumer side: what does an event subscriber receive when its UE moves to another AMF?
# TS 29.518 5.2.2.2.1.1 (target AMF "shall ... create event subscriptions for the UE specific events" and, if a new
# subscription Id is allocated, send it to the notification endpoint) and 5.3.2.4.1 (Notify "shall also be invoked ...
# when there is a change of AMF during UE mobility procedures, if the subscription Id changes").
# AMF1 (cafe00) and AMF2 (cb0100) are in different AMF sets, so the Id cannot be reused (NOTE in 5.2.2.2.1.1).
# Usage: AMF_IMAGE=... UE_IMAGE=... [AMF1_CFG=... GNB2_CFG=...] sh scripts/run_exp2_notify.sh <run-name>
set -u
cd "$(dirname "$0")/.." && docker compose config -q || { echo "compose config invalid"; exit 1; }
R=runs/${1:?run name}; mkdir -p "$R"
export UE_IMAGE=${UE_IMAGE:-free5gc/ueransim:latest}
echo "EXP=exp2_notify UE_IMAGE=$UE_IMAGE AMF_IMAGE=${AMF_IMAGE:-free5gc/amf:v4.3.0} AMF2_CFG=${AMF2_CFG:-amf2cfg.yaml} AMF1_CFG=${AMF1_CFG:-amf1cfg.yaml} GNB2_CFG=${GNB2_CFG:-gnb2cfg.yaml} SUBSCRIBER=${SUBSCRIBER:-subscriber.json} POST_WAIT=${POST_WAIT:-25} TAIL_WAIT=${TAIL_WAIT:-15}" > "$R/00_meta.txt"; date -u +%FT%TZ >> "$R/00_meta.txt"
pc() { docker exec probe curl -s --http2-prior-knowledge -w ' HTTP %{http_code}\n' "$@"; }
ts() { python3 -c 'import time;print(f"{time.time():.3f}")'; }
PATCH='[{"op":"replace","path":"/expiry","value":"2027-01-01T00:00:00Z"}]'
SUPI=imsi-208930000000001
SINK=http://probe.free5gc.org:9000

# 1. clean core, capture, notification sink
docker rm -f cap >/dev/null 2>&1
docker compose --profile ran --profile ue --profile pdu down -v >/dev/null 2>&1
docker compose up -d >/dev/null 2>&1; sleep 15
sh scripts/provision.sh >> "$R/00_meta.txt"
docker ps --format '{{.Names}} {{.ID}} {{.CreatedAt}}' >> "$R/00_meta.txt"
docker run -d --name cap --net host -v "$PWD/$R":/out nicolaka/netshoot \
  tcpdump -i br-twoamf -s 0 -w /out/sbi.pcap 'tcp port 8000 or tcp port 9000 or sctp' >/dev/null
docker exec -d probe sh -c 'rm -f /tmp/notify.log; while true; do printf "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n" | nc -l -p 9000 >> /tmp/notify.log 2>&1; echo "---conn-end $(date -u +%s)" >> /tmp/notify.log; done'
sleep 2

# 1b. sink self-test from AMF2: the sink is reachable from the target AMF and the capture sees it
{ echo "t=$(ts)"; docker exec amf2 wget -q -T 3 -O- --post-data '{"selftest":"amf2"}' "$SINK/selftest-from-amf2" 2>&1; echo "rc=$?"; } > "$R/01a_sink_selftest.txt"
sleep 1

# 2. register at AMF1, subscribe as an NF consumer acting on behalf of another NF (subsChangeNotifyUri present)
docker compose --profile ran --profile ue up -d gnb1 >/dev/null 2>&1; sleep 3
docker compose --profile ue up -d ue >/dev/null 2>&1; sleep 8
BODY='{"subscription":{"eventList":[{"type":"LOCATION_REPORT","immediateFlag":false},{"type":"REACHABILITY_REPORT","immediateFlag":false}],"eventNotifyUri":"'$SINK'/notify","notifyCorrelationId":"ch5-exp2n","subsChangeNotifyUri":"'$SINK'/subs-change","subsChangeNotifyCorrelationId":"ch5-exp2n-subs-change","nfId":"11111111-2222-3333-4444-555555555555","supi":"'$SUPI'"}}'
pc -X POST http://amf1.free5gc.org:8000/namf-evts/v1/subscriptions -H 'Content-Type: application/json' -d "$BODY" > "$R/01_create_sub_amf1.txt"
pc -X PATCH http://amf1.free5gc.org:8000/namf-evts/v1/subscriptions/1 -H 'Content-Type: application/json' -d "$PATCH" > "$R/02_patch_sub1_amf1_before.txt"

# 3. move the UE (gNB2 up, gNB1 down)
docker compose --profile ran up -d gnb2 >/dev/null 2>&1; sleep 4
echo "$(ts)" > "$R/t_move.txt"
docker stop gnb1 >/dev/null; sleep ${POST_WAIT:-25}

# 4. consumer view after the move
NEW='{"subscription":{"eventList":[{"type":"LOCATION_REPORT","immediateFlag":true}],"eventNotifyUri":"'$SINK'/notify-probe","notifyCorrelationId":"ch5-exp2n-probe","nfId":"11111111-2222-3333-4444-555555555555","supi":"'$SUPI'"}}'
echo "$(ts)" > "$R/t_probe.txt"
{ for a in amf1 amf2; do
    echo "== $a OAM"; docker exec probe curl -s http://$a.free5gc.org:8000/namf-oam/v1/registered-ue-context; echo
    echo "== $a PATCH sub 1"; pc -X PATCH http://$a.free5gc.org:8000/namf-evts/v1/subscriptions/1 -H 'Content-Type: application/json' -d "$PATCH"
    echo "== $a POST new UE subscription (immediate LOCATION_REPORT)"; pc -X POST http://$a.free5gc.org:8000/namf-evts/v1/subscriptions -H 'Content-Type: application/json' -d "$NEW"
  done
} > "$R/03_after_move_state.txt"
sleep ${TAIL_WAIT:-15}
{ echo "== notify sink log bytes"; docker exec probe sh -c 'wc -c < /tmp/notify.log'; } >> "$R/03_after_move_state.txt"
docker exec probe cat /tmp/notify.log > "$R/notify.raw" 2>/dev/null
echo "$(ts)" > "$R/t_end.txt"
sleep 1; docker stop cap >/dev/null; docker rm cap >/dev/null
for c in amf1 amf2 ue gnb1 gnb2 udm pcf; do docker logs $c 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$R/$c.log"; done
cat "$R/03_after_move_state.txt"
