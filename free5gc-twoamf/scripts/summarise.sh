#!/bin/sh
# One-line summary of an exp1 run directory.
R=$1
hdr=$(docker run --rm -v "$PWD/$R":/d nicolaka/netshoot tshark -r /d/sbi.pcap -Y 'ngap.procedureCode==15' -T fields -e nas_5gs.security_header_type -e nas_5gs.mm.5gs_reg_type 2>/dev/null | tr '\t\n' ':|')
xfer=$(grep -oE '\| [0-9]{3} \|[^|]*\| POST +\| /namf-comm/v1/ue-contexts/[^ ]*/transfer' $R/amf1.log | grep -oE '^\| [0-9]{3}' | tr -d '| ' | tr '\n' ',')
rej=$(grep -oE 'RegistrationReject \[[A-Za-z0-9]*\]|Capability5GMM is nil|INTEGRITY_CHECK_FAIL' $R/amf2.log | sort | uniq -c | tr -s ' ' | tr '\n' ';')
ue=$(grep -cE 'Initial Registration is successful' $R/ue.log)
amf2ue=$(sed -n '/== amf2 OAM/{n;p;}' $R/03_after_move_state.txt | cut -c1-40)
sub2=$(sed -n '/== amf2 PATCH/{n;p;}' $R/03_after_move_state.txt | grep -oE 'HTTP [0-9]+')
sink=$(sed -n '/notify sink/{n;p;}' $R/03_after_move_state.txt)
echo "$R | regs(sechdr:type)=$hdr | transfer=$xfer | amf2: $rej | UE reg-success=$ue | AMF2 ctx=$amf2ue | AMF2 sub1=$sub2 | notify bytes=$sink"
