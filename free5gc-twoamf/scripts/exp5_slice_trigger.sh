#!/bin/sh
# Experiment 5: UE-triggered AMF change with prior state.
# AMF1 serves slice A only; AMF2 serves A+B (different AMF set); gNB1 connects to both.
# 1) UE requests slice A only -> registers on AMF1; an event subscription is created at AMF1.
# 2) UE adds subscribed slice B (`slice-add`, TS 24.501 5.5.1.3.2) -> registration update requesting A+B
#    -> AMF1 cannot serve B -> AMF re-allocation to AMF2. 3) Probe where the UE and its state ended up.
# Usage: [env] sh scripts/exp5_slice_trigger.sh <run-name>
set -u
cd "$(dirname "$0")/.."
export AMF_IMAGE=${AMF_IMAGE:-ch5/free5gc-amf:fixed-trace-realloc} UE_IMAGE=${UE_IMAGE:-ch5/ueransim:patched6}
export AMF1_CFG=${AMF1_CFG:-amf1cfg_sliceA.yaml} AMF2_CFG=${AMF2_CFG:-amf2cfg_sliceAB.yaml}
export GNB1_CFG=${GNB1_CFG:-gnb1cfg_both_rev.yaml} UE_CFG=${UE_CFG:-uecfg_sliceA.yaml}
R=runs/$1; rm -rf $R; mkdir -p $R
env | grep -E "^(AMF_IMAGE|UE_IMAGE|AMF1_CFG|AMF2_CFG|GNB1_CFG|UE_CFG)=" > $R/00_meta.txt; date -u +%FT%TZ >> $R/00_meta.txt
pc() { docker exec probe curl -s --http2-prior-knowledge -w ' HTTP %{http_code}\n' "$@"; }
PATCH='[{"op":"replace","path":"/expiry","value":"2027-01-01T00:00:00Z"}]'
docker rm -f cap >/dev/null 2>&1
docker compose --profile ran --profile ue --profile pdu down -v >/dev/null 2>&1; docker compose up -d >/dev/null 2>&1; sleep 15
sh scripts/provision.sh >> $R/00_meta.txt 2>&1
docker run -d --name cap --net host -v "$PWD/$R":/out nicolaka/netshoot tcpdump -i br-twoamf -s 0 -w /out/sbi.pcap 'tcp port 8000 or sctp' >/dev/null 2>&1; sleep 2
docker compose --profile ran up -d gnb1 >/dev/null 2>&1; sleep 4; docker compose --profile ue up -d ue >/dev/null 2>&1; sleep 10
# phase 1 state at AMF1
BODY='{"subscription":{"eventList":[{"type":"LOCATION_REPORT","immediateFlag":false},{"type":"REACHABILITY_REPORT","immediateFlag":false}],"eventNotifyUri":"http://probe.free5gc.org:9000/notify","notifyCorrelationId":"ch5-exp5","nfId":"11111111-2222-3333-4444-555555555555","supi":"imsi-208930000000001"}}'
pc -X POST http://amf1.free5gc.org:8000/namf-evts/v1/subscriptions -H 'Content-Type: application/json' -d "$BODY" > $R/01_create_sub_amf1.txt
{ for a in amf1 amf2; do echo "== $a OAM"; docker exec probe curl -s http://$a.free5gc.org:8000/namf-oam/v1/registered-ue-context; echo; done; } > $R/02_before_trigger.txt
# phase 2: UE requests subscribed slice B
UEN=$(docker exec ue ./nr-cli --dump | head -1)
date -u +"%Y-%m-%d %H:%M:%S" > $R/03_trigger_time.txt
docker exec ue ./nr-cli "$UEN" -e "slice-add 1 112233" >> $R/03_trigger_time.txt 2>&1
sleep ${WAIT:-15}
{ for a in amf1 amf2; do echo "== $a OAM"; docker exec probe curl -s http://$a.free5gc.org:8000/namf-oam/v1/registered-ue-context; echo
    echo "== $a PATCH sub 1"; pc -X PATCH http://$a.free5gc.org:8000/namf-evts/v1/subscriptions/1 -H 'Content-Type: application/json' -d "$PATCH"; done; } > $R/04_after_trigger.txt
sleep 1; docker stop cap >/dev/null 2>&1; docker rm cap >/dev/null 2>&1
for c in amf1 amf2 ue gnb1 udm nssf; do docker logs $c 2>&1 | perl -pe 's/\x1b\[[0-9;]*m//g' > $R/$c.log; done
cat $R/04_after_trigger.txt
