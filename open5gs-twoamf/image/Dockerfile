# Open5GS built from source (arm64) for the Ch.5 two-AMF testbed.
FROM ubuntu:24.04 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y python3-pip python3-setuptools python3-wheel ninja-build build-essential \
    flex bison git cmake meson libsctp-dev libgnutls28-dev libgcrypt-dev libssl-dev libmongoc-dev libbson-dev \
    libyaml-dev libnghttp2-dev libmicrohttpd-dev libcurl4-gnutls-dev libtins-dev libtalloc-dev libidn-dev
ARG OPEN5GS_COMMIT=3e007ddf0175e806ad6f215460aa59a026004a48
RUN git clone https://github.com/open5gs/open5gs /src && cd /src && git checkout $OPEN5GS_COMMIT
WORKDIR /src
RUN meson setup build --prefix=/open5gs && ninja -C build install

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y libsctp1 libgnutls30t64 libgcrypt20 libssl3t64 libmongoc-1.0-0 libbson-1.0-0 \
    libyaml-0-2 libnghttp2-14 libmicrohttpd12t64 libcurl3t64-gnutls libtins4.5 libtalloc2 libidn12 iproute2 \
    && apt-get clean
COPY --from=build /open5gs /open5gs
ENV LD_LIBRARY_PATH=/open5gs/lib:/open5gs/lib/aarch64-linux-gnu
WORKDIR /open5gs
