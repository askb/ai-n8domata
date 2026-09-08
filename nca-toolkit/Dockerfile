# Custom NCA Toolkit image.
#
# Pins the upstream toolkit to the exact digest currently running in production
# (so the toolkit version never drifts unexpectedly) and refreshes yt-dlp.
#
# Why: YouTube regularly breaks older yt-dlp releases. When that happens the
# pinned-old yt-dlp shipped in the upstream image silently returns an EMPTY file
# and the toolkit's /v1/media/download responds HTTP 500 "downloaded file is
# empty", taking down every fresh download in the Longform2Shorts pipeline.
# It also surfaces as "HTTP Error 403: Forbidden" on formats that need current
# signature/SABR handling. The toolkit imports yt-dlp as a Python module
# (routes/v1/media/download.py: `import yt_dlp`), so the upgrade and retry
# hardening must land in the image, and a container restart is required for a
# new yt-dlp to be picked up by the running gunicorn workers.
#
# yt-dlp is intentionally kept current by bumping YTDLP_VERSION below, because
# it must track YouTube. See refresh-ytdlp.sh and TODO-MASTER-TRACKER N18.
#
# The base image runs as the non-root user `appuser`. Switch to root only to
# install into the system site-packages, then restore `appuser` for runtime so
# gunicorn keeps running unprivileged exactly like upstream.
FROM stephengpope/no-code-architects-toolkit@sha256:4b4e8702f9e4538280cabe32e850965cb988923aad8731c721d7922abbae3b6f

USER root

# yt-dlp needs a JavaScript runtime for YouTube signature/n-token decryption.
# Deno is the default supported runtime in yt-dlp's external JS runtime support.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
        amd64) deno_target="x86_64-unknown-linux-gnu" ;; \
        arm64) deno_target="aarch64-unknown-linux-gnu" ;; \
        *) echo "Unsupported architecture for Deno: ${arch}" >&2; exit 1 ;; \
    esac; \
    wget -q -O /usr/local/bin/deno.zip \
        "https://github.com/denoland/deno/releases/latest/download/deno-${deno_target}.zip"; \
    python -m zipfile -e /usr/local/bin/deno.zip /usr/local/bin; \
    rm /usr/local/bin/deno.zip; \
    chmod 0755 /usr/local/bin/deno; \
    deno --version

# yt-dlp MUST be pinned to an explicit version, even though it has to track
# YouTube. `pip install --upgrade yt-dlp` looks like it self-refreshes, but the
# RUN layer is cached forever: the version is frozen at whatever was current the
# first time the layer was built, and every later `docker compose build` reports
# CACHED and changes nothing. That is how this image sat on a June yt-dlp for
# three months while YouTube 403'd every 1080p download.
#
# Pinning makes the version visible in git and makes the layer cache key change
# when it is bumped, so a rebuild genuinely refreshes. Bump via refresh-ytdlp.sh
# (cron, weekly) or by hand:
#   docker compose build --build-arg YTDLP_VERSION=<ver> nca-toolkit
ARG YTDLP_VERSION=2026.8.19
RUN pip install --no-cache-dir "yt-dlp==${YTDLP_VERSION}" && \
    yt-dlp --version

# Harden NCA's yt-dlp defaults against transient YouTube 403 fragment failures.
COPY patch_download_retries.py /usr/local/bin/patch_download_retries.py
RUN python /usr/local/bin/patch_download_retries.py && \
    rm /usr/local/bin/patch_download_retries.py

USER appuser
