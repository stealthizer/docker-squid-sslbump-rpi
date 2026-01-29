#!/bin/bash
# encoding: utf-8

SQUID_USER=squid
SQUID_DIR=/usr/local/squid

if [ ! -f $SQUID_DIR/ssl/bluestar.pem ]; then
    openssl req -new -newkey rsa:2048 -nodes -days 3650 -x509 -keyout $SQUID_DIR/ssl/bluestar.pem -out $SQUID_DIR/ssl/bluestar.crt\
	    -subj "/C=US/ST=Texas/L=Austin/O=BlueStar/OU=NetworkSecurity/CN=bluestar"
    openssl x509 -in $SQUID_DIR/ssl/bluestar.crt -outform DER -out $SQUID_DIR/ssl/bluestar.der
fi

# Ensure required directories exist with proper permissions
mkdir -p $SQUID_DIR/var/logs
mkdir -p $SQUID_DIR/var/cache
mkdir -p $SQUID_DIR/var/lib/ssl_db
chown -R ${SQUID_USER}:${SQUID_USER} $SQUID_DIR/var
chown -R ${SQUID_USER}:${SQUID_USER} $SQUID_DIR/ssl

# Initialize SSL certificate database if needed
if [ ! -d "$SQUID_DIR/var/lib/ssl_db" ] || [ -z "$(ls -A $SQUID_DIR/var/lib/ssl_db)" ]; then
    $SQUID_DIR/libexec/security_file_certgen -c -s $SQUID_DIR/var/lib/ssl_db -M 4MB
    chown -R ${SQUID_USER}:${SQUID_USER} $SQUID_DIR/var/lib/ssl_db
fi

if [ $SAFESEARCH ]; then
	echo "216.239.38.120 youtube.com" >> /etc/hosts
	echo "216.239.38.120 www.youtube.com" >> /etc/hosts
	echo "216.239.38.120 m.youtube.com" >> /etc/hosts
	echo "216.239.38.120 youtubei.googleapis.com" >> /etc/hosts
	echo "216.239.38.120 youtube.googleapis.com" >> /etc/hosts
	echo "216.239.38.120 www.youtube-nocookie.com" >> /etc/hosts
	echo "216.239.38.120 www.google.com" >> /etc/hosts
fi

cleanup() {
    iptables -t nat -D OUTPUT -p tcp --syn --dport 80 -j REDIRECT --to-port 3130 2>/dev/null || true
    iptables -t nat -D PREROUTING -p tcp --syn --dport 80 -j REDIRECT --to-port 3130 2>/dev/null || true
    iptables -t nat -D OUTPUT -p tcp --syn --dport 443 -j REDIRECT --to-port 3131 2>/dev/null || true
    iptables -t nat -D PREROUTING -p tcp --syn --dport 443 -j REDIRECT --to-port 3131 2>/dev/null || true
    iptables -t nat -D OUTPUT -m owner --uid-owner squid -j RETURN 2>/dev/null || true
}
trap cleanup EXIT
cleanup

if [ $TRANSPARENT ]; then
    iptables -t nat -I OUTPUT 1 -p tcp --syn --dport 80 -j REDIRECT --to-port 3130
    iptables -t nat -I PREROUTING -p tcp --syn --dport 80 -j REDIRECT --to-port 3130
    iptables -t nat -I OUTPUT 1 -p tcp --syn --dport 443 -j REDIRECT --to-port 3131
    iptables -t nat -I PREROUTING -p tcp --syn --dport 443 -j REDIRECT --to-port 3131
    iptables -t nat -I OUTPUT 1 -m owner --uid-owner squid -j RETURN
fi

exec $SQUID_DIR/sbin/squid -f $SQUID_DIR/etc/squid.conf -NYCd 10
