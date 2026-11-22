#!/bin/sh
# Summarise Open5GS PDU-session runs (pdu_o5_r*): session at AMF1, transfer content, AMF2 SMF calls, Accept PDU status.
cd "$(dirname "$0")/../open5gs-twoamf/runs"
echo "run,pdu_established_amf1,sessions_in_transfer,amf2_to_smf_calls,accept_pdu_session_status,ue_reregistered"
for r in pdu_o5_r*; do
  est=$(grep -c "PDU Session establishment is successful" $r/ue.log)
  sess=$(docker run --rm -v $PWD/$r:/d nicolaka/netshoot tshark -r /d/sbi.pcap -d tcp.port==7777,http2 -Y 'http2.data.data and ip.src==10.110.0.5 and ip.dst==10.110.0.6' -T fields -e http2.data.data 2>/dev/null | head -1 | xxd -r -p | python3 -I -c "import sys,json;print(len(json.load(sys.stdin)['ueContext'].get('sessionContextList',[])))")
  calls=$(docker run --rm -v $PWD/$r:/d nicolaka/netshoot tshark -r /d/sbi.pcap -d tcp.port==7777,http2 -Y 'http2.headers.path and ip.src==10.110.0.6 and ip.dst==10.110.0.15' -T fields -e http2.headers.path 2>/dev/null | sed 's|.*/sm-contexts/[0-9]*/||' | tr '\n' ' ')
  st=$(grep -o "PDU Session Status : [0-9a-f]*" $r/amf2.log | tail -1 | awk '{print $NF}')
  ok=$(grep -c "Mobility Registration is successful" $r/ue.log)
  echo "$r,$est,$sess,$calls,$st,$ok"
done
