# syntax=docker/dockerfile:1

FROM alpine:3.19

LABEL maintainer="InnerWebBlueprint <hello@innerwebblueprint.com>"

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apk update && apk add --no-cache \
    bash rsyslog curl nano coreutils iputils unzip wget \
    supervisor \
    postfix dovecot dovecot-lmtpd dovecot-pigeonhole-plugin dovecot-pop3d \
    mariadb mariadb-client \
    ca-certificates openssl \
    nginx certbot certbot-nginx \
    php81 php81-fpm php81-mysqli php81-mbstring php81-session \
    php81-json php81-openssl php81-curl php81-zlib php81-xml \
    php81-dom php81-tokenizer php81-fileinfo


# Install Storj CLI (uplink)
RUN wget -O /tmp/uplink.zip https://github.com/storj/storj/releases/latest/download/uplink_linux_amd64.zip && \
    unzip /tmp/uplink.zip -d /tmp && \
    mv /tmp/uplink /usr/local/bin/uplink && \
    chmod +x /usr/local/bin/uplink && \
    rm -rf /tmp/uplink.zip /tmp/uplink

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
ADD includes/includes.cache-buster /tmp/includes.cache-buster
COPY includes/ .

# Ensure scripts are executable
RUN chmod +x /var/setup/scripts/* 

# Expose standard mail ports
EXPOSE 25 587 993 143 110 4190

# Use bash shell
SHELL ["/bin/bash", "-c"]

# Start container
ENTRYPOINT ["/var/setup/scripts/start.sh"]
