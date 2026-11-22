# free5GC AMF built from source (main @ b626080), optionally with the ch5 RINMR fix.
#   docker build --build-arg APPLY_FIX=0 -t ch5/free5gc-amf:main .     (control)
#   docker build --build-arg APPLY_FIX=1 -t ch5/free5gc-amf:fixed .    (fix)
#   docker build --build-arg APPLY_FIX=1 --build-arg TRACE=1 -t ch5/free5gc-amf:fixed-trace .  (fix + state-use trace)
#   docker build --build-arg APPLY_FIX=0 --build-arg TRACE=1 -t ch5/free5gc-amf:main-trace .   (control + trace)
#   docker build --build-arg APPLY_FIX=1 --build-arg TRACE=1 --build-arg REALLOC=1 -t ch5/free5gc-amf:fixed-trace-realloc .  (+ re-allocation target fix)
#   docker build --build-arg APPLY_FIX=1 --build-arg GUTI_REPAIR=1 -t ch5/free5gc-amf:fixed-gutirepair .  (+ new 5G-GUTI after AMF change)
FROM golang:1.26-alpine AS build
RUN apk add --no-cache git
ARG AMF_COMMIT=b62608072087102cd3154d6fc5552376e0697e47
ARG APPLY_FIX=0
RUN git clone https://github.com/free5gc/amf /src && cd /src && git checkout $AMF_COMMIT
ARG FIX_PATCH=ch5-decipher-container-after-transfer.patch
COPY ${FIX_PATCH} /tmp/fix.patch
WORKDIR /src
RUN if [ "$APPLY_FIX" = "1" ]; then git apply /tmp/fix.patch && git diff --stat; fi
ARG TRACE=0
COPY ch5_trace.go /tmp/ch5_trace.go
RUN if [ "$TRACE" = "1" ]; then cp /tmp/ch5_trace.go internal/gmm/ && \
    sed -i 's|^\(\t*\)ue.CopyDataFromUeContextModel(ueContextTransferRspData.UeContext)|\1ch5TraceReceived(ue, ueContextTransferRspData.UeContext)\n\1ue.CopyDataFromUeContextModel(ueContextTransferRspData.UeContext)\n\1ch5TraceState(ue, "copied")|' internal/gmm/handler.go && \
    sed -i 's|^\(\t*\)gmm_message.SendRegistrationAccept(|\1ch5TraceState(ue, "accept")\n\1gmm_message.SendRegistrationAccept(|' internal/gmm/handler.go && \
    grep -c ch5Trace internal/gmm/handler.go; fi
ARG REALLOC=0
COPY ch5-realloc-target-ranue.patch ch5-realloc-trace.patch ch5-realloc2-step8.patch ch5-realloc2-trace.patch /tmp/
# REALLOC=1: re-allocation target fix only.  REALLOC=2: + realloc2 (TS 23.502 4.2.2.2.3 step 7(A)/8).
RUN if [ "$REALLOC" = "1" ]; then git apply /tmp/ch5-realloc-target-ranue.patch && \
    if [ "$TRACE" = "1" ]; then git apply /tmp/ch5-realloc-trace.patch; fi && git diff --stat; fi
RUN if [ "$REALLOC" = "2" ]; then git apply /tmp/ch5-realloc-target-ranue.patch && git apply /tmp/ch5-realloc2-step8.patch && \
    if [ "$TRACE" = "1" ]; then git apply /tmp/ch5-realloc2-trace.patch; fi && git diff --stat; fi
ARG GUTI_REPAIR=0
COPY ch5-guti-repair.patch /tmp/
# GUTI_REPAIR=1: the new AMF allocates its own 5G-GUTI after an AMF change (TS 33.501 6.12.3). Needs APPLY_FIX=1.
RUN if [ "$GUTI_REPAIR" = "1" ]; then git apply /tmp/ch5-guti-repair.patch && git diff --stat; fi
RUN CGO_ENABLED=0 go build -o /amf ./cmd

FROM free5gc/amf:v4.3.0
COPY --from=build /amf /free5gc/amf
