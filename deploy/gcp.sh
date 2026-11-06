#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
ZONE="${ZONE:-us-west1-b}"
INSTANCE="${INSTANCE:-flake-chicken-api}"
NETWORK="${NETWORK:-default}"
GO_BIN="${GO_BIN:-go}"
API_TAG="flake-chicken-api"
API_RULE="flake-chicken-api-8080"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "Set PROJECT_ID or configure a gcloud project first." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/build/server"
(
  cd "$ROOT_DIR/server"
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 "$GO_BIN" build \
    -trimpath -ldflags='-s -w' -o "$ROOT_DIR/build/server/server" .
)

gcloud services enable compute.googleapis.com --project="$PROJECT_ID" --quiet

if ! gcloud compute firewall-rules describe "$API_RULE" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute firewall-rules create "$API_RULE" \
    --project="$PROJECT_ID" --network="$NETWORK" \
    --direction=INGRESS --allow=tcp:8080 \
    --source-ranges=0.0.0.0/0 --target-tags="$API_TAG" --quiet
fi

if ! gcloud compute instances describe "$INSTANCE" \
  --project="$PROJECT_ID" --zone="$ZONE" >/dev/null 2>&1; then
  gcloud compute instances create "$INSTANCE" \
    --project="$PROJECT_ID" --zone="$ZONE" \
    --machine-type=e2-micro \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=10GB --boot-disk-type=pd-standard \
    --network="$NETWORK" --network-tier=STANDARD \
    --tags="$API_TAG" --labels=app=flake-chicken \
    --no-service-account --no-scopes --shielded-secure-boot --quiet
fi

# Wait until the new VM has started sshd before copying the binary.
SSH_READY=false
for attempt in {1..18}; do
  if gcloud compute ssh "$INSTANCE" --project="$PROJECT_ID" --zone="$ZONE" \
    --quiet --ssh-flag='-o ConnectTimeout=5' --command=true; then
    SSH_READY=true
    break
  fi
  sleep 5
done
if [[ "$SSH_READY" != true ]]; then
  echo "SSH did not become ready; the VM exists. Rerun this script to deploy." >&2
  exit 1
fi

gcloud compute scp "$ROOT_DIR/build/server/server" \
  "$ROOT_DIR/deploy/flake-chicken.service" "$INSTANCE:~/" \
  --project="$PROJECT_ID" --zone="$ZONE" --quiet

gcloud compute ssh "$INSTANCE" --project="$PROJECT_ID" --zone="$ZONE" \
  --quiet --command='set -eu
    sudo install -d -m 755 /opt/flake-chicken
    sudo install -m 755 "$HOME/server" /opt/flake-chicken/server.new
    sudo mv /opt/flake-chicken/server.new /opt/flake-chicken/server
    sudo install -m 644 "$HOME/flake-chicken.service" /etc/systemd/system/flake-chicken.service
    sudo systemctl daemon-reload
    sudo systemctl enable flake-chicken.service
    sudo systemctl restart flake-chicken.service
    sudo systemctl is-active flake-chicken.service'

SERVER_IP="$(gcloud compute instances describe "$INSTANCE" \
  --project="$PROJECT_ID" --zone="$ZONE" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
curl --fail --silent --show-error --retry 5 --retry-connrefused \
  --connect-timeout 10 --max-time 15 "http://$SERVER_IP:8080/healthz"
echo
echo "API: http://$SERVER_IP:8080/healthz"
