FROM debian:bookworm-slim

ARG ZIG_TARGET=aarch64-linux
ARG ZIG_CHANNEL=master

ENV ZIG_TARGET=${ZIG_TARGET}
ENV ZIG_CHANNEL=${ZIG_CHANNEL}
ENV ZIG_INSTALL_DIR=/opt/zig
ENV ZIG_SOURCE=iridoporth-docker-build
ENV ZIG_CURL_CONNECT_TIMEOUT=10
ENV ZIG_CURL_MAX_TIME=120
ENV ZIG_CURL_RETRIES=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        xz-utils \
        build-essential \
        git \
        jq \
        minisign \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/install-zig-from-mirrors.sh /usr/local/bin/install-zig-from-mirrors

RUN sh /usr/local/bin/install-zig-from-mirrors

ENV PATH="/opt/zig:${PATH}"

RUN zig version
