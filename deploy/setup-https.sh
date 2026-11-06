#!/usr/bin/env bash
# Run as root on the existing Debian VM. Keep the reserved external IP.
set -euo pipefail
APP_IP=35.212.249.154
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq caddy python3-venv ca-certificates sqlite3
python3 -m venv /opt/flake-certbot
/opt/flake-certbot/bin/pip install --quiet 'certbot>=5.4,<6'
install -d -m 755 /var/lib/letsencrypt
install -d -o root -g caddy -m 750 /etc/caddy/ip-certificate
cat > /usr/local/sbin/flake-certificate-deploy <<'HOOK'
#!/bin/sh
set -eu
lineage="${RENEWED_LINEAGE:-/etc/letsencrypt/live/35.212.249.154}"
install -o root -g caddy -m 640 "$lineage/fullchain.pem" /etc/caddy/ip-certificate/fullchain.pem
install -o root -g caddy -m 640 "$lineage/privkey.pem" /etc/caddy/ip-certificate/privkey.pem
systemctl reload caddy
HOOK
chmod 750 /usr/local/sbin/flake-certificate-deploy
if [ ! -f "/etc/letsencrypt/live/$APP_IP/fullchain.pem" ]; then
  cat > /etc/caddy/Caddyfile <<'CADDY'
:80 {
  root * /var/lib/letsencrypt
  file_server
}
CADDY
  systemctl restart caddy
  /opt/flake-certbot/bin/certbot certonly --staging --required-profile shortlived \
    --webroot --webroot-path /var/lib/letsencrypt --ip-address "$APP_IP" \
    --cert-name "$APP_IP" --agree-tos --register-unsafely-without-email --non-interactive \
    --config-dir /var/lib/flake-acme-staging/config --work-dir /var/lib/flake-acme-staging/work --logs-dir /var/lib/flake-acme-staging/logs
  /opt/flake-certbot/bin/certbot certonly --required-profile shortlived \
    --webroot --webroot-path /var/lib/letsencrypt --ip-address "$APP_IP" \
    --cert-name "$APP_IP" --agree-tos --register-unsafely-without-email --non-interactive
fi
/usr/local/sbin/flake-certificate-deploy
cat > /etc/caddy/Caddyfile <<'CADDY'
{
  auto_https off
  default_sni 35.212.249.154
}
:80 {
  handle /.well-known/acme-challenge/* {
    root * /var/lib/letsencrypt
    file_server
  }
  handle {
    redir https://35.212.249.154{uri} permanent
  }
}
https://35.212.249.154 {
  tls /etc/caddy/ip-certificate/fullchain.pem /etc/caddy/ip-certificate/privkey.pem
  encode zstd gzip
  reverse_proxy 127.0.0.1:8080 {
    flush_interval -1
  }
}
CADDY
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy
install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
ln -sf /usr/local/sbin/flake-certificate-deploy /etc/letsencrypt/renewal-hooks/deploy/flake-chicken
cat > /etc/systemd/system/flake-certificate-renew.service <<'SERVICE'
[Unit]
Description=Renew the Flake Chicken short-lived IP certificate
After=network-online.target
[Service]
Type=oneshot
ExecStart=/opt/flake-certbot/bin/certbot renew --quiet
SERVICE
cat > /etc/systemd/system/flake-certificate-renew.timer <<'TIMER'
[Unit]
Description=Check the Flake Chicken IP certificate every three hours
[Timer]
OnCalendar=*-*-* 00/3:00:00
RandomizedDelaySec=10m
Persistent=true
[Install]
WantedBy=timers.target
TIMER
systemctl daemon-reload
systemctl enable --now flake-certificate-renew.timer
openssl x509 -in /etc/caddy/ip-certificate/fullchain.pem -noout -dates -ext subjectAltName
