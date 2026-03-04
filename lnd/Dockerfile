FROM debian:bookworm-slim

ARG LND_VERSION=v0.18.3-beta
ARG TARGETPLATFORM

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    gosu \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Download and verify LND
RUN set -ex; \
    case "${TARGETPLATFORM:-linux/amd64}" in \
      "linux/amd64") LND_ARCH="linux-amd64" ;; \
      "linux/arm64") LND_ARCH="linux-arm64" ;; \
      *) echo "Unsupported platform"; exit 1 ;; \
    esac; \
    curl -sSL "https://github.com/lightningnetwork/lnd/releases/download/${LND_VERSION}/lnd-${LND_ARCH}-${LND_VERSION}.tar.gz" -o /tmp/lnd.tar.gz; \
    curl -sSL "https://github.com/lightningnetwork/lnd/releases/download/${LND_VERSION}/manifest-${LND_VERSION}.txt" -o /tmp/manifest.txt; \
    grep "lnd-${LND_ARCH}-${LND_VERSION}.tar.gz" /tmp/manifest.txt | sha256sum -c -; \
    tar -xzf /tmp/lnd.tar.gz -C /tmp; \
    install -m 0755 -o root -g root -t /usr/local/bin /tmp/lnd-${LND_ARCH}-${LND_VERSION}/lnd; \
    install -m 0755 -o root -g root -t /usr/local/bin /tmp/lnd-${LND_ARCH}-${LND_VERSION}/lncli; \
    rm -rf /tmp/lnd*; \
    rm -f /tmp/manifest.txt

# Create lnd user and data directory
RUN groupadd --gid 1001 lnd \
    && useradd --uid 1001 --gid lnd --shell /bin/bash --create-home lnd

ENV LND_DATA=/home/lnd/.lnd

RUN mkdir -p ${LND_DATA} \
    && chown -R lnd:lnd ${LND_DATA}

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Lightning P2P
EXPOSE 9735
# gRPC API
EXPOSE 10009
# REST API
EXPOSE 8080
# Watchtower server (Alice only, but exposed for all)
EXPOSE 9911

VOLUME ["/home/lnd/.lnd"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["lnd"]
