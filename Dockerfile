# syntax=docker/dockerfile:1

# Stage 1: Build Akash provider-services binary
FROM golang:1.23-alpine AS akash-builder
RUN apk add --no-cache git curl
WORKDIR /build
RUN AKASH_VERSION=$(curl -s https://api.github.com/repos/akash-network/provider/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4) && \
    echo "Building Akash provider-services ${AKASH_VERSION}..." && \
    git clone --depth 1 --branch ${AKASH_VERSION} https://github.com/akash-network/provider.git && \
    cd provider && \
    GOTOOLCHAIN=auto CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -mod=readonly \
    -tags "osusergo,netgo,static_build" \
    -ldflags="-s -w \
    -X github.com/akash-network/provider/version.Name=provider-services \
    -X github.com/akash-network/provider/version.AppName=provider-services \
    -X github.com/akash-network/provider/version.Version=${AKASH_VERSION}" \
    -o /build/provider-services \
    ./cmd/provider-services && \
    echo "✓ provider-services ${AKASH_VERSION} compiled successfully"

# Stage 2: Build Pigeonhole with unfinished extensions (for ereject support)
FROM alpine:3.21 AS pigeonhole-builder
RUN apk add --no-cache \
    git cmake make gcc g++ libc-dev automake autoconf libtool \
    dovecot dovecot-dev valgrind
WORKDIR /build
RUN DOVECOT_VERSION=$(dovecot --version | cut -d' ' -f1) && \
    echo "Building Pigeonhole for Dovecot ${DOVECOT_VERSION} with ereject support..." && \
    git clone --depth 1 --branch release-0.5.21 https://github.com/dovecot/pigeonhole.git && \
    cd pigeonhole && \
    ./autogen.sh && \
    ./configure --with-dovecot=/usr/lib/dovecot && \
    CPPFLAGS="-DHAVE_SIEVE_UNFINISHED" make && \
    make install-strip DESTDIR=/build/pigeonhole-install && \
    echo "✓ Pigeonhole compiled with unfinished extensions enabled"

# Stage 3: Main application image
FROM alpine:3.21

LABEL maintainer="InnerWebBlueprint <hello@innerwebblueprint.com>"

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
# Core system utilities and setup tools
RUN apk update && apk add --no-cache \
    bash rsyslog curl nano coreutils iputils zip unzip wget supervisor cronie dnsmasq tree sudo jq bc netcat-openbsd

# Python & build tools
RUN apk add --no-cache \
    python3 py3-pip py3-cryptography py3-setuptools py3-wheel py3-yaml py3-requests \
    gcc musl-dev libffi-dev openssl-dev

# Mail stack: Postfix, Dovecot (without pigeonhole - we'll install custom build)
RUN apk add --no-cache \
    postfix postfix-mysql \
    dovecot dovecot-lmtpd dovecot-pop3d dovecot-mysql \
    rspamd redis mailx

# Copy custom-built Pigeonhole with ereject support from builder
COPY --from=pigeonhole-builder /build/pigeonhole-install/usr/lib/dovecot/ /usr/lib/dovecot/
COPY --from=pigeonhole-builder /build/pigeonhole-install/usr/libexec/dovecot/ /usr/libexec/dovecot/
COPY --from=pigeonhole-builder /build/pigeonhole-install/usr/bin/ /usr/bin/
COPY --from=pigeonhole-builder /build/pigeonhole-install/usr/share/doc/dovecot/ /usr/share/doc/dovecot/

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

# pip install beem

# Node.js and npm - install from Alpine 3.21 packages and validate compatibility
RUN echo "Fetching n8n's Node.js requirements..." && \
    N8N_NODE_REQUIREMENT=$(curl -s https://raw.githubusercontent.com/n8n-io/n8n/master/package.json | grep -o '"node": *"[^"]*"' | cut -d'"' -f4) && \
    echo "n8n requires Node.js: $N8N_NODE_REQUIREMENT" && \
    echo "Installing Node.js from Alpine 3.21 packages..." && \
    apk add --no-cache nodejs npm && \
    INSTALLED_VERSION=$(node --version) && \
    echo "Installed Node.js version: $INSTALLED_VERSION" && \
    echo "Note: Using Alpine 3.21's Node.js $INSTALLED_VERSION which is compatible with n8n" && \
    echo "✓ Node.js installation complete" && \
    node --version && npm --version

RUN ln -sf /usr/bin/php83 /usr/bin/php

# Install n8n and create dedicated user
RUN npm install -g n8n

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
COPY --from=akash-builder /build/provider-services /usr/local/bin/provider-services
RUN chmod +x /usr/local/bin/provider-services

# Install wp-cli and allow root usage
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp-cli.phar && \
    printf '#!/bin/sh\nexec /usr/local/bin/wp-cli.phar --allow-root "$@"\n' > /usr/local/bin/wp && \
    chmod +x /usr/local/bin/wp

# Install iwb-akash-deploy from GitHub repository 
RUN cd /tmp && \
    wget https://github.com/innerwebblueprint/iwb-akash-deploy/raw/refs/heads/master/iwb-akash-deploy.py -O iwb-akash-deploy && \
    mv iwb-akash-deploy /usr/local/bin/iwb-akash-deploy && \
    chmod +x /usr/local/bin/iwb-akash-deploy && \
    echo "✓ iwb-akash-deploy installed to /usr/local/bin"

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

# Configure sudo for n8n user to run only provider-services as root
# not sure this is actually needed? 
# Not sure I am using these wrapper scripts or not
# Commenting out to see if it breaks
#RUN echo "n8n ALL=(root) NOPASSWD: /usr/local/bin/provider-services" > /etc/sudoers.d/n8n && \
#    chmod 440 /etc/sudoers.d/n8n && \
#    touch /var/log/n8n-commands.log && \
#    chown n8n:n8n /var/log/n8n-commands.log 

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
