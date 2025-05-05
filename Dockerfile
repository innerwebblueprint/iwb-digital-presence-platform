# syntax=docker/dockerfile:1

FROM alpine:3.19

LABEL maintainer="InnerWebBlueprint <hello@innerwebblueprint.com>"

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apk update && apk add --no-cache \
    # Postfix + Dovecot + Rspamd
    postfix postfix-mysql dovecot dovecot-lmtpd dovecot-pigeonhole-plugin dovecot-pop3d dovecot-mysql rspamd redis mailx \
    # MariaDB
    mariadb mariadb-client \
    # Certbot + Nginx
    nginx certbot certbot-nginx \
    # PHP
    php81 php81-cli php81-fpm php81-mysqli php81-mbstring php81-session php81-json php81-openssl php81-curl php81-phar \
    php81-zlib php81-xml php81-dom php81-tokenizer php81-fileinfo php81-imap php81-gd php81-intl php81-pdo php81-pdo_mysql php81-soap \
    # System Utilities
    bash rsyslog curl nano coreutils iputils unzip wget supervisor cronie dnsmasq \
    # Python
    python3 py3-pip py3-cryptography py3-setuptools py3-wheel gcc musl-dev libffi-dev openssl-dev

# pip install beem

RUN ln -sf /usr/bin/php81 /usr/bin/php

# Install Storj CLI (uplink)
RUN wget -O /tmp/uplink.zip https://github.com/storj/storj/releases/latest/download/uplink_linux_amd64.zip && \
    unzip /tmp/uplink.zip -d /tmp && \
    mv /tmp/uplink /usr/local/bin/uplink && \
    chmod +x /usr/local/bin/uplink && \
    rm -rf /tmp/uplink.zip /tmp/uplink

# Install wp-cli and allow root usage
# RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
#     chmod +x wp-cli.phar && \
#     mv wp-cli.phar /usr/local/bin/wp-cli.phar && \
#     echo -e '#!/bin/sh\nexec /usr/local/bin/wp-cli.phar --allow-root "$@"' > /usr/local/bin/wp && \
#     chmod +x /usr/local/bin/wp

RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x wp-cli.phar && \
    mv wp-cli.phar /usr/local/bin/wp-cli.phar && \
    printf '#!/bin/sh\nexec /usr/local/bin/wp-cli.phar --allow-root "$@"\n' > /usr/local/bin/wp && \
    chmod +x /usr/local/bin/wp


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
ADD includes/includes.cache-buster /tmp/includes.cache-buster
COPY includes/ .

# Ensure scripts are executable
RUN chmod -R +x /var/setup/scripts/* 

# Expose standard mail ports
EXPOSE 25 587 993 143 110 4190

# Use bash shell
SHELL ["/bin/bash", "-c"]

# Start container
ENTRYPOINT ["/var/setup/scripts/start.sh"]
