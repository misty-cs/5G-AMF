#!/bin/sh
# Summarise free5GC PDU-session runs (pdu_f5*): session at AMF1, transfer content, SMF calls after the move, sessions at accept.
cd "$(dirname "$0")/../twoamf/runs"
echo "run,pdu_established,sessions_in_transfer,smf_calls_after_move(src:op),sessions_at_serving_amf_accept,ue_reregistered"
for r in pdu_f5*; do
  est=$(grep -c "PDU Session establishment is successful" $r/ue.log)
  if echo $r | grep -q ctl; then
    sess="n/a(same AMF)"; acc=$(grep -o "ch5trace accept .*" $r/amf1.log | tail -1 | grep -o '"sessionContexts":[0-9]*' | cut -d: -f2)
  else
    sess=$(grep -o "ch5trace received .*" $r/amf2.log | sed 's/ch5trace received //' | python3 -I -c "import sys,json;d=json.loads(sys.stdin.read() or '{}');print(len(d.get('sessionContextList',[])))")
    acc=$(grep -o "ch5trace accept .*" $r/amf2.log | tail -1 | grep -o '"sessionContexts":[0-9]*' | cut -d: -f2)
  fi
  calls=$(docker run --rm -v $PWD/$r:/d nicolaka/netshoot tshark -r /d/sbi.pcap -d tcp.port==8000,http2 -Y 'http2.headers.path contains "sm-contexts" and frame.time_relative > 20' -T fields -e ip.src -e http2.headers.path 2>/dev/null | sed -e 's/10.100.200.16/AMF1/' -e 's/10.100.200.17/AMF2/' -e 's|/nsmf-pdusession/v1/sm-contexts/[^/]*/*||' | awk '{print $1":"($2==""?"create":$2)}' | tr '\n' ' ')
  ok=$(grep -cE "(Mobility|Initial) Registration is successful" $r/ue.log)
  echo "$r,$est,$sess,$calls,$acc,$ok"
done
