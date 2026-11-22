# UERANSIM with one conformance fix for the Ch.5 testbed.
# TS 24.501 §5.5.1.3.5, cause #10 (mobility/periodic registration reject):
#   the UE "shall delete any mapped 5G NAS security context or partial native 5G NAS
#   security context" -> the current native context must be kept, so the following
#   initial registration is integrity protected (§4.4.4.1, §4.4.6).
# Upstream clears m_currentNsCtx on #10; this build keeps it (only the non-current context is dropped).
# Patch 2: TS 24.501 4.4.2.1.2 only requires marking the copy *stored on the USIM / non-volatile memory*
#   invalid when initial registration starts; the in-memory current context stays valid and is used to
#   protect the REGISTRATION REQUEST (4.4.6 b). Upstream wipes the in-memory context; this build does not.
FROM gcc:14.3.0 AS builder
ARG UERANSIM_COMMIT=4f45e18f80b0684f7d6e29f1fea0f579e9243d68
RUN apt-get update && apt-get install -y libsctp-dev lksctp-tools iproute2 make cmake
RUN git clone https://github.com/aligungr/UERANSIM /UERANSIM && cd /UERANSIM && git checkout $UERANSIM_COMMIT
WORKDIR /UERANSIM
RUN f=src/ue/nas/mm/register.cpp; \
    n=$(grep -n 'if (cause == nas::EMmCause::IMPLICITY_DEREGISTERED)' $f | head -1 | cut -d: -f1); \
    sed -n "$((n+2))p" $f | grep -q 'm_usim->m_currentNsCtx = {};' && \
    sed -i "$((n+2))s|m_usim->m_currentNsCtx = {};|/* ch5 patch: keep current native NAS security context (TS 24.501 5.5.1.3.5 #10) */|" $f && \
    sed -n "$n,$((n+4))p" $f && grep -q 'ch5 patch' $f
RUN f=src/ue/nas/mm/register.cpp; \
    n=$(grep -n 'as invalid when the UE' $f | head -1 | cut -d: -f1); \
    sed -n "$((n+2))p" $f | grep -q 'm_usim->m_currentNsCtx = {};' && \
    sed -i "$((n+2))s|m_usim->m_currentNsCtx = {};|/* ch5 patch 2: keep in-memory context (TS 24.501 4.4.2.1.2 applies to stored copy) */|" $f && \
    sed -n "$((n-1)),$((n+2))p" $f && grep -q "ch5 patch 2" $f
# Patch 3: same 4.4.2.1.2 sentence, misapplied on leaving 5GMM-DEREGISTERED (base.cpp onSwitchMmState).
RUN f=src/ue/nas/mm/base.cpp; \
    grep -q 'if (oldState == EMmState::MM_DEREGISTERED && newState != EMmState::MM_DEREGISTERED && newState != EMmState::MM_NULL)' $f && \
    sed -i 's|if (oldState == EMmState::MM_DEREGISTERED \&\& newState != EMmState::MM_DEREGISTERED \&\& newState != EMmState::MM_NULL)|if (false /* ch5 patch 3: TS 24.501 4.4.2.1.2 applies to stored copy */ \&\& oldState == EMmState::MM_DEREGISTERED)|' $f && \
    grep -n 'ch5 patch 3' $f
# Patch 4: TS 24.501 4.4.6 - Requested NSSAI is not a cleartext IE; upstream leaves it in the outer
#   REGISTRATION REQUEST next to the NAS message container (Open5GS rejects that with #95).
RUN f=src/ue/nas/mm/messaging.cpp; \
    grep -q 'regReq.ladnIndication = std::nullopt;' $f && \
    sed -i 's|regReq.ladnIndication = std::nullopt;|regReq.ladnIndication = std::nullopt;\n        regReq.requestedNSSAI = std::nullopt; /* ch5 patch 4 */|' $f && \
    grep -n 'ch5 patch 4' $f
# Patch 5 (gNB): TS 38.413 8.6.2.2 / 8.3.1.2 -- on a DOWNLINK NAS TRANSPORT or INITIAL CONTEXT SETUP
#   REQUEST that carries the Old AMF IE from a different AMF, re-associate the UE with that AMF and
#   adopt its AMF UE NGAP ID (needed for AMF re-allocation by direct forwarding). Enabled by PATCH5=1.
ARG PATCH5=0
COPY ch5-patch5-gnb-amf-realloc.patch /tmp/
RUN if [ "$PATCH5" = "1" ]; then git apply /tmp/ch5-patch5-gnb-amf-realloc.patch && git diff --stat; fi
# Patch 6 (UE): adds `nr-cli <ue> -e "slice-add <sst> <sd-hex>"`, which appends a slice to the configured
#   NSSAI and starts a mobility registration update with cause SLICE_CHANGE (TS 24.501 5.5.1.3.2). The cause
#   exists upstream but nothing triggers it. Enabled by PATCH6=1.
ARG PATCH6=0
COPY ch5-patch6-ue-slice-add.patch /tmp/
RUN if [ "$PATCH6" = "1" ]; then git apply /tmp/ch5-patch6-ue-slice-add.patch && git diff --stat; fi
# Patch 7 (UE): the mobility/periodic REGISTRATION REQUEST carries the ngKSI of the current native 5G NAS
#   security context, as the initial REGISTRATION REQUEST already does. Upstream sendMobilityRegistration
#   never sets it, so the message says "no key available" (7) and every mobility registration forces
#   re-authentication. Enabled by PATCH7=1.
ARG PATCH7=0
RUN if [ "$PATCH7" = "1" ]; then f=src/ue/nas/mm/register.cpp; \
    n=$(grep -n 'request->ueSecurityCapability = createSecurityCapabilityIe();' $f | sed -n 2p | cut -d: -f1); \
    sed -i "${n}a if (m_usim->m_currentNsCtx) { request->nasKeySetIdentifier.tsc = m_usim->m_currentNsCtx->tsc; request->nasKeySetIdentifier.ksi = m_usim->m_currentNsCtx->ngKsi; } /* ch5 patch 7 */" $f && \
    grep -n 'ch5 patch 7' $f; fi
RUN make -j"$(nproc)"

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y libsctp1 lksctp-tools iproute2 iputils-ping procps && apt-get clean
# iproute2 in trixie ships rt_tables under /usr/share; UERANSIM's TUN setup reads /etc/iproute2/rt_tables
RUN mkdir -p /etc/iproute2 && (test -f /etc/iproute2/rt_tables || cp /usr/share/iproute2/rt_tables /etc/iproute2/rt_tables)
WORKDIR /ueransim
RUN mkdir -p config
COPY --from=builder /UERANSIM/build/nr-gnb /UERANSIM/build/nr-ue /UERANSIM/build/nr-cli ./
VOLUME ["/ueransim/config"]
