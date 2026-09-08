#!/bin/bash
# refresh-ytdlp.sh
# Keep the nca-toolkit image's yt-dlp current with YouTube.
#
# YouTube breaks older yt-dlp releases every few weeks; when it does, every
# Longform2Shorts download fails with "HTTP Error 403: Forbidden" or an empty
# file. The Dockerfile used to say "rebuild periodically to refresh yt-dlp",
# but `pip install --upgrade yt-dlp` is a cached layer, so rebuilding was a
# no-op and the image stayed on a June yt-dlp for three months.
#
# This pins the build to the current PyPI release, which changes the layer
# cache key and so actually rebuilds. Restarting the container matters too: the
# toolkit does `import yt_dlp`, so gunicorn workers keep the old module in
# memory until they are replaced.
#
# Run weekly via the systemd --user timer in this directory
# (refresh-ytdlp.timer), or by hand.

set -euo pipefail

# Repo root holds docker-compose.yml; this script lives in deploy/systemd/.
COMPOSE_DIR="${COMPOSE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SERVICE="nca-toolkit"
CONTAINER="${NCA_CONTAINER:-n8n-nca-toolkit}"

log() { echo "[$(date -Is)] $*"; }

current="$(docker exec "$CONTAINER" yt-dlp --version 2>/dev/null | tr -d '[:space:]' || echo "none")"
latest="$(curl -fsSL --max-time 30 https://pypi.org/pypi/yt-dlp/json \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["version"])')"

if [ -z "$latest" ]; then
    log "ERROR: could not resolve latest yt-dlp from PyPI" >&2
    exit 1
fi

log "yt-dlp running=$current latest=$latest"

# pip normalises 2026.8.19 and 2026.08.19 to the same release, so compare loosely.
norm() { echo "${1//.0/.}"; }
if [ "$(norm "$current")" = "$(norm "$latest")" ]; then
    log "already current, nothing to do"
    exit 0
fi

cd "$COMPOSE_DIR"
log "rebuilding $SERVICE with YTDLP_VERSION=$latest"
docker compose build --build-arg "YTDLP_VERSION=$latest" "$SERVICE"

log "recreating $CONTAINER so gunicorn reimports yt_dlp"
docker compose up -d "$SERVICE"

# Wait for the toolkit to answer again before declaring success.
for _ in $(seq 1 30); do
    if docker exec "$CONTAINER" yt-dlp --version >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

installed="$(docker exec "$CONTAINER" yt-dlp --version 2>/dev/null | tr -d '[:space:]' || echo "none")"
if [ "$(norm "$installed")" != "$(norm "$latest")" ]; then
    log "ERROR: expected yt-dlp $latest but container reports $installed" >&2
    exit 1
fi

log "yt-dlp refreshed to $installed"
