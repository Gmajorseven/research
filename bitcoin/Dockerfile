FROM debian:bookworm-slim

ARG BITCOIN_VERSION=29.3
ARG TARGETPLATFORM

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    ca-certificates \
    gosu \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# Download and verify Bitcoin Core
RUN set -ex; \
    case "${TARGETPLATFORM:-linux/amd64}" in \
      "linux/amd64") BITCOIN_ARCH="x86_64-linux-gnu" ;; \
      "linux/arm64") BITCOIN_ARCH="aarch64-linux-gnu" ;; \
      *) echo "Unsupported platform"; exit 1 ;; \
    esac; \
    curl -sSL "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}-${BITCOIN_ARCH}.tar.gz" -o /tmp/bitcoin-${BITCOIN_VERSION}-${BITCOIN_ARCH}.tar.gz; \
    curl -sSL "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS" -o /tmp/SHA256SUMS; \
    cd /tmp && grep "bitcoin-${BITCOIN_VERSION}-${BITCOIN_ARCH}.tar.gz" /tmp/SHA256SUMS | sha256sum -c -; \
    tar -xzf /tmp/bitcoin-${BITCOIN_VERSION}-${BITCOIN_ARCH}.tar.gz -C /tmp; \
    install -m 0755 -o root -g root -t /usr/local/bin /tmp/bitcoin-${BITCOIN_VERSION}/bin/bitcoind; \
    install -m 0755 -o root -g root -t /usr/local/bin /tmp/bitcoin-${BITCOIN_VERSION}/bin/bitcoin-cli; \
    rm -rf /tmp/bitcoin*; \
    rm -f /tmp/SHA256SUMS

# Create bitcoin user and data directory
RUN groupadd --gid 1000 bitcoin \
    && useradd --uid 1000 --gid bitcoin --shell /bin/bash --create-home bitcoin

ENV BITCOIN_DATA=/home/bitcoin/.bitcoin

RUN mkdir -p ${BITCOIN_DATA} \
    && chown -R bitcoin:bitcoin ${BITCOIN_DATA}

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# regtest P2P port
EXPOSE 18444
# regtest RPC port
EXPOSE 18443
# ZMQ rawblock (shared across networks)
EXPOSE 28332
# ZMQ rawtx
EXPOSE 28333

VOLUME ["/home/bitcoin/.bitcoin"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bitcoind"]
