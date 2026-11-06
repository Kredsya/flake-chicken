#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
ZONE="${ZONE:-us-west1-b}"
INSTANCE="${INSTANCE:-flake-chicken-api}"
GO_BIN="${GO_BIN:-go}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
SERVER_ENV_FILE="${SERVER_ENV_FILE:-$ROOT_DIR/build/deploy/server.env}"
if [[ ! -s "$SERVER_ENV_FILE" ]]; then
  echo "Provide SERVER_ENV_FILE with PUBLIC_ORIGIN, DATABASE_PATH, GOOGLE_CLOUD_PROJECT and GOOGLE_MAPS_API_KEY." >&2
  exit 1
fi
# The existing VM, reserved IP, TLS and FCM service account are provisioned separately.
gcloud compute instances describe "$INSTANCE" --project="$PROJECT_ID" --zone="$ZONE" --format='value(status)'
mkdir -p "$ROOT_DIR/build/server"
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build web --release --no-wasm-dry-run)
(cd "$ROOT_DIR" && "$FLUTTER_BIN" build apk --release)
tar -czf "$ROOT_DIR/build/server/web.tar.gz" -C "$ROOT_DIR/build/web" .
(cd "$ROOT_DIR/server" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 "$GO_BIN" build \
  -trimpath -ldflags='-s -w' -o "$ROOT_DIR/build/server/server" .)
gcloud compute scp "$ROOT_DIR/build/server/server" "$ROOT_DIR/build/server/web.tar.gz" \
  "$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk" \
  "$ROOT_DIR/deploy/flake-chicken.service" "$SERVER_ENV_FILE" "$INSTANCE:~/" \
  --project="$PROJECT_ID" --zone="$ZONE" --quiet
# Copy under a fixed name so custom local environment filenames also work.
if [[ "$(basename "$SERVER_ENV_FILE")" != server.env ]]; then
  gcloud compute scp "$SERVER_ENV_FILE" "$INSTANCE:~/server.env" --project="$PROJECT_ID" --zone="$ZONE" --quiet
fi
gcloud compute ssh "$INSTANCE" --project="$PROJECT_ID" --zone="$ZONE" --quiet \
 --ssh-flag='-o ConnectTimeout=10' --command='set -eu
  sudo install -d -m 755 /opt/flake-chicken
  sudo install -d -m 755 /opt/flake-chicken/downloads
  sudo install -m 644 "$HOME/app-release.apk" /opt/flake-chicken/downloads/flake-chicken.apk.new
  sudo mv /opt/flake-chicken/downloads/flake-chicken.apk.new /opt/flake-chicken/downloads/flake-chicken.apk
  sudo install -d -m 700 /etc/flake-chicken /var/backups/flake-chicken
  if [ -f /var/lib/flake-chicken/app.db ]; then
    sudo sqlite3 /var/lib/flake-chicken/app.db ".backup /var/backups/flake-chicken/before-deploy.db"
    sudo chmod 600 /var/backups/flake-chicken/before-deploy.db
  fi
  sudo install -m 600 "$HOME/server.env" /etc/flake-chicken/server.env
  rm "$HOME/server.env"
  sudo rm -rf /opt/flake-chicken/web.new
  sudo install -d -m 755 /opt/flake-chicken/web.new
  sudo tar -xzf "$HOME/web.tar.gz" -C /opt/flake-chicken/web.new
  sudo chmod -R a+rX /opt/flake-chicken/web.new
  sudo ln -s /opt/flake-chicken/downloads /opt/flake-chicken/web.new/downloads
  sudo rm -rf /opt/flake-chicken/web.previous
  if [ -d /opt/flake-chicken/web ]; then sudo mv /opt/flake-chicken/web /opt/flake-chicken/web.previous; fi
  sudo mv /opt/flake-chicken/web.new /opt/flake-chicken/web
  sudo install -m 755 "$HOME/server" /opt/flake-chicken/server.new
  sudo mv /opt/flake-chicken/server.new /opt/flake-chicken/server
  sudo install -m 644 "$HOME/flake-chicken.service" /etc/systemd/system/flake-chicken.service
  sudo systemctl daemon-reload
  sudo systemctl enable flake-chicken.service
  sudo systemctl restart flake-chicken.service
  sudo systemctl is-active flake-chicken.service'
curl --fail --silent --show-error --retry 5 --retry-connrefused --connect-timeout 10 --max-time 20 \
 https://35.212.249.154/healthz
echo
echo 'Web: https://35.212.249.154/'
echo 'QR: https://35.212.249.154/install.html'
echo 'APK: https://35.212.249.154/downloads/flake-chicken.apk'
