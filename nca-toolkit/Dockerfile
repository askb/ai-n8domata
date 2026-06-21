# Custom NCA Toolkit image.
#
# Pins the upstream toolkit to the exact digest currently running in production
# (so the toolkit version never drifts unexpectedly) and refreshes yt-dlp.
#
# Why: YouTube regularly breaks older yt-dlp releases. When that happens the
# pinned-old yt-dlp shipped in the upstream image silently returns an EMPTY file
# and the toolkit's /v1/media/download responds HTTP 500 "downloaded file is
# empty", taking down every fresh download in the Longform2Shorts pipeline.
# The toolkit imports yt-dlp as a Python module (routes/v1/media/download.py:
# `import yt_dlp`), so the upgrade and retry hardening must land in the image.
#
# yt-dlp is intentionally installed with `--upgrade` (latest at build time)
# rather than pinned, because it must track YouTube. Rebuild this image
# periodically to refresh yt-dlp. See TODO-MASTER-TRACKER N18.
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

# yt-dlp is deliberately unpinned (must track YouTube); ignore the pin-version rule.
# hadolint ignore=DL3013
RUN pip install --no-cache-dir --upgrade yt-dlp

# Harden NCA's yt-dlp defaults against transient YouTube 403 fragment failures.
COPY patch_download_retries.py /usr/local/bin/patch_download_retries.py
RUN python /usr/local/bin/patch_download_retries.py && \
    rm /usr/local/bin/patch_download_retries.py

USER appuser
