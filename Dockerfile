# syntax=docker/dockerfile:1

FROM alpine:3.21

LABEL maintainer="InnerWebBlueprint <hello@innerwebblueprint.com>"

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
# Core system utilities and setup tools
RUN apk update && apk add --no-cache \
    bash rsyslog curl nano coreutils iputils unzip wget supervisor cronie dnsmasq tree sudo jq bc netcat-openbsd

# Python & build tools
RUN apk add --no-cache \
    python3 py3-pip py3-cryptography py3-setuptools py3-wheel py3-yaml py3-requests \
    gcc musl-dev libffi-dev openssl-dev

# Mail stack: Postfix, Dovecot, Rspamd
RUN apk add --no-cache \
    postfix postfix-mysql \
    dovecot dovecot-lmtpd dovecot-pigeonhole-plugin dovecot-pop3d dovecot-mysql \
    rspamd redis mailx

# Database: MariaDB server and client
RUN apk add --no-cache mariadb mariadb-client

# Web stack: Nginx and Certbot
RUN apk add --no-cache nginx certbot certbot-nginx

# PHP 8.3 core + WordPress modules
RUN apk add --no-cache \
    php83 php83-cli php83-fpm php83-common php83-mysqli php83-mbstring php83-session php83-json \
    php83-openssl php83-curl php83-phar php83-zlib php83-xml php83-dom php83-tokenizer php83-fileinfo \
    php83-imap php83-gd php83-intl php83-pdo php83-pdo_mysql php83-soap \
    php83-ctype

# PHP extensions for cryptography and large numbers
RUN apk add --no-cache php83-gmp php83-bcmath

# PHP extensions for media, uploads, and encoding
RUN apk add --no-cache \
    php83-exif php83-zip php83-iconv php83-pecl-imagick imagemagick

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

# Install Storj CLI (uplink)
RUN wget -O /tmp/uplink.zip https://github.com/storj/storj/releases/latest/download/uplink_linux_amd64.zip && \
    unzip /tmp/uplink.zip -d /tmp && \
    mv /tmp/uplink /usr/local/bin/uplink && \
    chmod +x /usr/local/bin/uplink && \
    rm -rf /tmp/uplink.zip /tmp/uplink

# Install Akash CLI (provider-services)
RUN cd /tmp && \
    curl -sfL https://raw.githubusercontent.com/akash-network/provider/main/install.sh | bash && \
    mv ./bin/provider-services /usr/local/bin/provider-services && \
    chmod +x /usr/local/bin/provider-services && \
    rm -rf ./bin

# Install iwb-akash-deploy from GitHub repository
RUN cd /tmp && \
    wget https://github.com/innerwebblueprint/iwb-akash-deploy/raw/refs/heads/master/iwb-akash-deploy.py -O iwb-akash-deploy && \
    mv iwb-akash-deploy /usr/local/bin/iwb-akash-deploy && \
    chmod +x /usr/local/bin/iwb-akash-deploy && \
    echo "✓ iwb-akash-deploy installed to /usr/local/bin"

# Install wp-cli and allow root usage
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp-cli.phar && \
    printf '#!/bin/sh\nexec /usr/local/bin/wp-cli.phar --allow-root "$@"\n' > /usr/local/bin/wp && \
    chmod +x /usr/local/bin/wp

# Install n8n and create dedicated user
RUN npm install -g n8n

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

# Install PostfixAdmin 
WORKDIR /var/www/html/postfixadmin
RUN wget https://github.com/postfixadmin/postfixadmin/archive/refs/tags/postfixadmin-3.3.13.tar.gz \
    && tar -xzf postfixadmin-3.3.13.tar.gz --strip-components=1 \
    && rm postfixadmin-3.3.13.tar.gz \
    && chown -R nginx:nginx /var/www/html/postfixadmin/


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
