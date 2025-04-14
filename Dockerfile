# syntax=docker/dockerfile:1

FROM alpine:3.19

LABEL maintainer="InnerWebBlueprint <hello@innerwebblueprint.com>"

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apk update && apk add --no-cache \
    bash \
    rsyslog \
    supervisor \
    curl \
    nano \
    coreutils \
    iputils \
    postfix \
    dovecot \
    dovecot-lmtpd \
    dovecot-pigeonhole-plugin \
    mariadb mariadb-client \
    ca-certificates

# Ensure correct vmail user and group
RUN deluser vmail 2>/dev/null || true && \
    delgroup vmail 2>/dev/null || true && \
    addgroup -g 10000 vmail && \
    adduser -D -u 10000 -G vmail -s /sbin/nologin -h /var/mail vmail

# Mail storage directory
RUN mkdir -p /var/mail/vmail && \
    chown -R vmail:vmail /var/mail/vmail && \
    chmod -R 770 /var/mail/vmail

# Placeholder configs and script
COPY docker/scripts/start.sh /usr/local/bin/start.sh
COPY docker/configs/supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY docker/configs/postfix/postfix-main.cf.template /var/mail/conf/postfix-main.cf.template
COPY docker/configs/postfix/postfix-master.cf /var/mail/conf/postfix-master.cf

COPY docker/configs/dovecot/dovecot-99-local.conf /var/mail/conf/dovecot-99-local.conf

COPY docker/configs/rsyslogd/rsyslogd-10-postfix.conf /var/mail/conf/rsyslogd-10-postfix.conf
COPY docker/configs/supervisord/supervisord.conf /var/mail/conf/supervisord.conf

# Ensure script is executable
RUN chmod +x /usr/local/bin/start.sh

# Expose standard mail ports
EXPOSE 25 587 993 143 4190

# Set working directory
WORKDIR /var

# Use bash shell
SHELL ["/bin/bash", "-c"]

# Start container
ENTRYPOINT ["/usr/local/bin/start.sh"]
