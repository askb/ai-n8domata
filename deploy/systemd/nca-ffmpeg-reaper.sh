#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
##############################################################################
# Reap orphaned / runaway ffmpeg processes inside the nca-toolkit container.
#
# The no-code-architects-toolkit launches ffmpeg as a subprocess per render and
# does NOT kill it when the API client disconnects or cancels the job. A runaway
# graph (e.g. an infinite `loop=-1` filter) therefore keeps an ffmpeg pegged at
# 100% CPU indefinitely, starving every other render on the box. This is a
# safety net: it SIGKILLs any ffmpeg in the container that has been running
# longer than a generous cap (real renders here finish in well under a minute).
#
# Config (env, all optional):
#   NCA_CONTAINER          container name        (default: n8n-nca-toolkit)
#   NCA_REAPER_MAX_SECONDS kill ffmpeg older than (default: 1200 = 20 min)
#
# Intended to run from a systemd --user timer every few minutes. Requires the
# invoking user to have docker access.
##############################################################################
set -euo pipefail

CONTAINER="${NCA_CONTAINER:-n8n-nca-toolkit}"
MAX_SECONDS="${NCA_REAPER_MAX_SECONDS:-1200}"

log() { printf '%s nca-ffmpeg-reaper: %s\n' "$(date -u +%FT%TZ)" "$*"; }

if ! command -v docker >/dev/null 2>&1; then
    log "ERROR: docker not found on PATH"
    exit 1
fi

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
    log "container '$CONTAINER' not running; nothing to do"
    exit 0
fi

# procps 'etimes' = elapsed time in whole seconds. The header line is skipped
# naturally because its COMMAND column is not "ffmpeg".
mapfile -t victims < <(
    docker exec "$CONTAINER" ps -eo pid,etimes,comm 2>/dev/null \
        | awk -v max="$MAX_SECONDS" '$3 == "ffmpeg" && ($2 + 0) > max { print $1 "|" $2 }'
)

if [ "${#victims[@]}" -eq 0 ]; then
    log "ok: no ffmpeg running longer than ${MAX_SECONDS}s"
    exit 0
fi

killed=0
for v in "${victims[@]}"; do
    pid="${v%%|*}"
    age="${v##*|}"
    log "killing runaway ffmpeg pid=${pid} age=${age}s (cap ${MAX_SECONDS}s)"
    if docker exec "$CONTAINER" kill -9 "$pid" 2>/dev/null; then
        killed=$((killed + 1))
    else
        log "WARN: could not kill pid=${pid} (already gone?)"
    fi
done

log "reaped ${killed}/${#victims[@]} runaway ffmpeg process(es)"
