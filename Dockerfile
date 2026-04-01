# syntax=docker/dockerfile:1

# Stage 1: Build Akash provider-services binary
FROM golang:1.25-alpine AS akash-builder
ARG AKASH_VERSION=latest
RUN apk add --no-cache git curl jq wget ca-certificates build-base linux-headers pkgconf eudev-dev
ENV PATH="/usr/local/go/bin:${PATH}"
WORKDIR /build
RUN set -e; \
    if [ "$AKASH_VERSION" = "latest" ]; then \
    AKASH_VERSION=$(curl -fsSL https://api.github.com/repos/akash-network/provider/releases/latest | jq -r '.tag_name'); \
    fi; \
    test -n "$AKASH_VERSION"; \
    echo "Attempting Akash provider-services source build for ${AKASH_VERSION}..."; \
    rm -rf /build/provider; \
    git clone --depth 1 --branch "$AKASH_VERSION" https://github.com/akash-network/provider.git /build/provider; \
    WASMVM_VERSION=$(cd /build/provider && go list -mod=readonly -m -f '{{ .Version }}' github.com/CosmWasm/wasmvm/v3); \
    mkdir -p /build/provider/.cache/lib; \
    wget -q -O /build/provider/.cache/lib/libwasmvm_muslc.x86_64.a "https://github.com/CosmWasm/wasmvm/releases/download/${WASMVM_VERSION}/libwasmvm_muslc.x86_64.a"; \
    if (cd /build/provider && \
    GOTOOLCHAIN=local CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
    go build -mod=readonly \
    -tags "osusergo,netgo,muslc,gcc,ledger" \
    -ldflags="-s -w -linkmode=external -extldflags \"-L/build/provider/.cache/lib -lm -Wl,-z,muldefs\" \
    -X github.com/akash-network/provider/version.Name=provider-services \
    -X github.com/akash-network/provider/version.AppName=provider-services \
    -X github.com/akash-network/provider/version.Version=${AKASH_VERSION}" \
    -o /build/provider-services \
    ./cmd/provider-services); then \
    echo "✓ provider-services ${AKASH_VERSION} compiled successfully"; \
    else \
    echo "ERROR: provider-services build failed for required version ${AKASH_VERSION}"; \
    exit 1; \
    fi; \
    echo "$AKASH_VERSION" > /build/provider-services.version

# Stage 2: Build Pigeonhole with unfinished extensions (for ereject support)
FROM alpine:3.21 AS pigeonhole-builder
RUN apk add --no-cache \
    git cmake make gcc g++ libc-dev automake autoconf libtool \
    dovecot dovecot-dev valgrind openssl-dev
WORKDIR /build
RUN DOVECOT_VERSION=$(dovecot --version | cut -d' ' -f1) && \
    echo "Building Pigeonhole for Dovecot ${DOVECOT_VERSION} with ereject support..." && \
    git clone --depth 1 --branch release-0.5 https://github.com/dovecot/pigeonhole.git && \
    cd pigeonhole && \
    echo "=== Patching source to enable ereject unconditionally ===" && \
    find . -name "*.c" -o -name "*.h" | xargs grep -l "HAVE_SIEVE_UNFINISHED" | while read file; do \
    echo "Patching $file" && \
    sed -i 's/#ifdef HAVE_SIEVE_UNFINISHED/#if 1/g' "$file" && \
    sed -i 's/#ifndef HAVE_SIEVE_UNFINISHED/#if 0/g' "$file"; \
    done && \
    echo "=== Building Pigeonhole ===" && \
    ./autogen.sh && \
    ./configure --with-dovecot=/usr/lib/dovecot && \
    make && \
    make install-strip DESTDIR=/build/pigeonhole-install && \
    echo "✓ Pigeonhole compiled with ereject enabled" && \
    echo "=== Verifying ereject in compiled library ===" && \
    strings /build/pigeonhole-install/usr/lib/dovecot/libdovecot-sieve.so.0.0.0 | grep -i ereject && \
    echo "✓ ereject found in library" && \
    echo "Installed files:" && \
    find /build/pigeonhole-install -type f | sort

# Stage 3: Main application image
FROM alpine:3.21

LABEL maintainer="InnerWebBlueprint <hello@innerwebblueprint.com>"

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
# Core system utilities and setup tools
RUN apk update && apk add --no-cache \
    bash rsyslog curl nano coreutils iputils zip unzip wget supervisor cronie dnsmasq tree sudo jq bc netcat-openbsd aws-cli eudev-libs

# Python & build tools
RUN apk add --no-cache \
    python3 py3-pip py3-cryptography py3-setuptools py3-wheel py3-yaml py3-requests \
    gcc musl-dev libffi-dev openssl-dev

# Mail stack: Postfix, Dovecot, Pigeonhole (Alpine package for proper linking)
RUN apk add --no-cache \
    postfix postfix-mysql \
    dovecot dovecot-lmtpd dovecot-pop3d dovecot-mysql dovecot-pigeonhole-plugin \
    rspamd redis mailx && \
    echo "=== Alpine's Sieve plugins ===" && \
    ls -lh /usr/lib/dovecot/*sieve* 2>/dev/null || echo "No sieve files found"

# Overwrite Sieve plugin libraries with custom ereject-enabled version
# Keep Alpine's executables (managesieve-login etc) for proper symbol linking  
COPY --from=pigeonhole-builder /build/pigeonhole-install/usr/lib/dovecot/lib90_sieve_plugin.so /usr/lib/dovecot/
COPY --from=pigeonhole-builder /build/pigeonhole-install/usr/lib/dovecot/lib95_imap_filter_sieve_plugin.so /usr/lib/dovecot/
COPY --from=pigeonhole-builder /build/pigeonhole-install/usr/lib/dovecot/lib95_imap_sieve_plugin.so /usr/lib/dovecot/
COPY --from=pigeonhole-builder /build/pigeonhole-install/usr/lib/dovecot/libdovecot-sieve.so.0.0.0 /usr/lib/dovecot/
COPY --from=pigeonhole-builder /build/pigeonhole-install/usr/lib/dovecot/sieve/ /usr/lib/dovecot/sieve/
RUN echo "=== Verification: Custom Sieve plugins installed ===" && \
    ls -lh /usr/lib/dovecot/*sieve* && \
    echo "=== Checking for ereject in main library ===" && \
    strings /usr/lib/dovecot/libdovecot-sieve.so.0.0.0 | grep -i ereject && \
    echo "=== ManageSieve executables (Alpine's for proper linking) ===" && \
    ls -lh /usr/libexec/dovecot/managesieve*

# Database: MariaDB server and client
RUN apk add --no-cache mariadb mariadb-client

# Web stack: Nginx and Certbot
RUN apk add --no-cache nginx certbot certbot-nginx

# PHP 8.3 core + WordPress modules
RUN apk add --no-cache \
    php83 php83-cli php83-fpm php83-common php83-mysqli php83-mbstring php83-session php83-json \
    php83-openssl php83-curl php83-phar php83-zlib php83-xml php83-dom php83-tokenizer php83-fileinfo \
    php83-imap php83-gd php83-intl php83-pdo php83-pdo_mysql php83-soap \
    php83-ctype php83-simplexml php83-xmlwriter

# PHP extensions for cryptography and large numbers
RUN apk add --no-cache php83-gmp php83-bcmath

# PHP extensions and media processing tools
RUN apk add --no-cache \
    php83-exif php83-zip php83-iconv php83-pecl-imagick imagemagick ffmpeg

# Node.js and npm runtime for n8n
RUN apk add --no-cache nodejs npm && \
    echo "Installed Node.js version: $(node --version)" && \
    echo "Installed npm version: $(npm --version)"

RUN ln -sf /usr/bin/php83 /usr/bin/php

# Install PostfixAdmin 
WORKDIR /var/www/html/postfixadmin
RUN wget https://github.com/postfixadmin/postfixadmin/archive/refs/tags/postfixadmin-3.3.13.tar.gz \
    && tar -xzf postfixadmin-3.3.13.tar.gz --strip-components=1 \
    && rm postfixadmin-3.3.13.tar.gz \
    && chown -R nginx:nginx /var/www/html/postfixadmin/

# Install Storj CLI (uplink)
RUN wget -O /tmp/uplink.zip https://github.com/storj/storj/releases/latest/download/uplink_linux_amd64.zip && \
    unzip /tmp/uplink.zip -d /tmp && \
    mv /tmp/uplink /usr/local/bin/uplink && \
    chmod +x /usr/local/bin/uplink && \
    rm -rf /tmp/uplink.zip /tmp/uplink

# Copy Akash provider-services binary from builder stage
COPY --from=akash-builder --chmod=755 /build/provider-services /usr/local/bin/provider-services

# Install wp-cli and allow root usage
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp-cli.phar && \
    printf '#!/bin/sh\nexec /usr/local/bin/wp-cli.phar --allow-root "$@"\n' > /usr/local/bin/wp && \
    chmod +x /usr/local/bin/wp

# Install fonts for imagemagik
RUN apk add --no-cache \
    msttcorefonts-installer && update-ms-fonts && fc-cache -f

# Install fonts for ASS subtitles
RUN apk add --no-cache \
    font-noto \
    font-dejavu \
    font-liberation \
    ttf-liberation \
    && fc-cache -f

# Create n8n user and group
RUN addgroup -g 9001 n8n && \
    adduser -D -u 9001 -G n8n -s /bin/bash -h /home/n8n n8n

# Create n8n data directory with proper ownership
RUN mkdir -p /var/www/html/n8n /home/n8n && \
    chown -R n8n:n8n /var/www/html/n8n /home/n8n && \
    ln -sf /var/www/html/n8n /home/n8n/.n8n && \
    chmod 700 /var/www/html/n8n

# Resolve n8n version late so version bumps only rebuild the small tail of the image.
ARG N8N_VERSION

# Validate Node.js compatibility and install the resolved stable n8n version.
RUN test -n "$N8N_VERSION" && \
    echo "Fetching Node.js requirements for n8n@$N8N_VERSION..." && \
    N8N_NODE_REQUIREMENT=$(NPM_CONFIG_CACHE=/tmp/.npm npm view "n8n@${N8N_VERSION}" engines.node) && \
    echo "n8n@$N8N_VERSION requires Node.js: $N8N_NODE_REQUIREMENT" && \
    echo "Using Node.js version: $(node --version)" && \
    echo "Installing n8n version: $N8N_VERSION" && \
    NPM_CONFIG_CACHE=/tmp/.npm npm install -g --no-audit --no-fund "n8n@${N8N_VERSION}" && \
    rm -rf /tmp/.npm && \
    echo "Installed n8n version: $(n8n --version)"

# Configure sudo for n8n user to run only provider-services as root
# not sure this is actually needed? 
# Not sure I am using these wrapper scripts or not
# Commenting out to see if it breaks
#RUN echo "n8n ALL=(root) NOPASSWD: /usr/local/bin/provider-services" > /etc/sudoers.d/n8n && \
#    chmod 440 /etc/sudoers.d/n8n && \
#    touch /var/log/n8n-commands.log && \
#    chown n8n:n8n /var/log/n8n-commands.log 

# Install iwb-akash-deploy from GitHub repository 
ARG IWB_AKASH_DEPLOY_CACHE_BUST=0
RUN cd /tmp && \
    echo "IWB_AKASH_DEPLOY_CACHE_BUST=${IWB_AKASH_DEPLOY_CACHE_BUST}" && \
    wget https://github.com/innerwebblueprint/iwb-akash-deploy/raw/refs/heads/master/iwb-akash-deploy.py -O iwb-akash-deploy && \
    mv iwb-akash-deploy /usr/local/bin/iwb-akash-deploy && \
    chmod +x /usr/local/bin/iwb-akash-deploy && \
    echo "✓ iwb-akash-deploy installed to /usr/local/bin"


# Ensure correct vmail user and group
RUN deluser vmail 2>/dev/null || true && \
    delgroup vmail 2>/dev/null || true && \
    addgroup -g 10000 vmail && \
    adduser -D -u 10000 -G vmail -s /sbin/nologin -h /var/mail vmail

# Mail storage directory
RUN mkdir -p /var/mail/vmail && \
    chown -R vmail:vmail /var/mail/vmail && \
    chmod -R 770 /var/mail/vmail

# Set working directory
WORKDIR /var

# Placeholder configs and script
COPY includes/ .

# Configure scripts and permissions
RUN chmod -R +x /var/setup/scripts

# Expose ports
EXPOSE 25 587 993 143 110 4190 5678

# Use bash shell
SHELL ["/bin/bash", "-c"]

# Start container
ENTRYPOINT ["/var/setup/scripts/start.sh"]
