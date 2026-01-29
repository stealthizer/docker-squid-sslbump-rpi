# Build stage
FROM debian:trixie AS builder

ENV SQUID_DIR=/usr/local/squid
ENV SQUID_LINK=https://github.com/squid-cache/squid/releases/download/SQUID_7_4/squid-7.4.tar.bz2
ENV SQUID_VERSION=7.4

# Install build dependencies
RUN apt-get update && \
    apt-get -qq -y install \
    build-essential \
    libssl-dev \
    wget \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download and extract Squid
RUN wget -q $SQUID_LINK && \
    tar xjf squid-${SQUID_VERSION}.tar.bz2 && \
    rm squid-${SQUID_VERSION}.tar.bz2

# Build Squid
RUN cd squid-${SQUID_VERSION} && \
    ./configure \
    --prefix=$SQUID_DIR \
    --enable-ssl \
    --with-openssl \
    --enable-ssl-crtd \
    --with-large-files \
    --enable-auth \
    --enable-icap-client && \
    make -j$(nproc) && \
    make install

# Configure Squid
RUN echo "#====added config===" >> $SQUID_DIR/etc/squid.conf && \
    echo "cache_effective_user squid" >> $SQUID_DIR/etc/squid.conf && \
    echo "cache_effective_group squid" >> $SQUID_DIR/etc/squid.conf && \
    echo "always_direct allow all" >> $SQUID_DIR/etc/squid.conf && \
    echo "icap_service_failure_limit -1" >> $SQUID_DIR/etc/squid.conf && \
    echo "ssl_bump server-first all" >> $SQUID_DIR/etc/squid.conf && \
    echo "sslproxy_cert_error allow all" >> $SQUID_DIR/etc/squid.conf && \
    echo "tls_outgoing_options flags=DONT_VERIFY_PEER" >> $SQUID_DIR/etc/squid.conf && \
    sed "/^http_port 3128$/d" -i $SQUID_DIR/etc/squid.conf && \
    sed "s/^http_access allow localnet$/http_access allow all/" -i $SQUID_DIR/etc/squid.conf && \
    sed "/^http_port 3130 intercept/d" -i $SQUID_DIR/etc/squid.conf && \
    echo "sslcrtd_program $SQUID_DIR/libexec/security_file_certgen -s $SQUID_DIR/var/lib/ssl_db -M 4MB" >> $SQUID_DIR/etc/squid.conf && \
    echo "https_port 3131 intercept ssl-bump generate-host-certificates=on dynamic_cert_mem_cache_size=4MB cert=$SQUID_DIR/ssl/bluestar.crt key=$SQUID_DIR/ssl/bluestar.pem" >> $SQUID_DIR/etc/squid.conf && \
    echo "http_port 3128 ssl-bump generate-host-certificates=on dynamic_cert_mem_cache_size=4MB cert=$SQUID_DIR/ssl/bluestar.crt key=$SQUID_DIR/ssl/bluestar.pem" >> $SQUID_DIR/etc/squid.conf

# Runtime stage
FROM debian:trixie-slim

ENV SQUID_USER=squid
ENV SQUID_DIR=/usr/local/squid

# Install only runtime dependencies
RUN apt-get update && \
    apt-get -qq -y install \
    openssl \
    libssl3t64 \
    iptables \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy built Squid from builder
COPY --from=builder $SQUID_DIR $SQUID_DIR

# Create necessary directories and user
RUN mkdir -p $SQUID_DIR/var/lib && \
    mkdir -p $SQUID_DIR/ssl && \
    mkdir -p $SQUID_DIR/var/cache && \
    mkdir -p $SQUID_DIR/var/logs && \
    useradd $SQUID_USER -U -b $SQUID_DIR && \
    $SQUID_DIR/libexec/security_file_certgen -c -s $SQUID_DIR/var/lib/ssl_db -M 4MB && \
    chown -R ${SQUID_USER}:${SQUID_USER} $SQUID_DIR


EXPOSE 3128
# For transparent proxy we are using the following ports
EXPOSE 3130
EXPOSE 3131

ADD ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
