# systemd units

Host-side `systemd --user` units for the AI-Automata stack.

## nca-ffmpeg-reaper

Safety net for the nca-toolkit container. NCA does not kill its ffmpeg
subprocess when an API client disconnects or cancels a job, so a runaway
graph (e.g. an infinite `loop=-1` filter) can keep an ffmpeg pegged at
100% CPU indefinitely and starve every other render. The reaper SIGKILLs
any ffmpeg in the container running longer than a generous cap.

Files:

- `nca-ffmpeg-reaper.sh` — kill ffmpeg older than the cap
- `nca-ffmpeg-reaper.service` — `oneshot` wrapper for the script
- `nca-ffmpeg-reaper.timer` — runs the service every 5 minutes

Config (env, optional):

- `NCA_CONTAINER` — container name (default `n8n-nca-toolkit`)
- `NCA_REAPER_MAX_SECONDS` — kill ffmpeg older than this (default `1200`)

### Install

```bash
cd deploy/systemd
install -m 0755 nca-ffmpeg-reaper.sh ~/scripts/
install -m 0644 nca-ffmpeg-reaper.service ~/.config/systemd/user/
install -m 0644 nca-ffmpeg-reaper.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now nca-ffmpeg-reaper.timer
```

For the timer to run while logged out, enable lingering once:

```bash
sudo loginctl enable-linger "$USER"
```

## refresh-ytdlp

Keeps yt-dlp current inside the nca-toolkit image. YouTube breaks older
yt-dlp releases every few weeks; when it does, every Longform2Shorts
download fails with `HTTP Error 403: Forbidden` (or produces an empty
file) and the whole pipeline stops.

The Dockerfile previously ran `pip install --upgrade yt-dlp`, which reads
as self-refreshing but is a **cached layer** — every later
`docker compose build` reported `CACHED` and changed nothing, so the image
sat on a June yt-dlp for three months. yt-dlp is now pinned to an explicit
`YTDLP_VERSION` build arg, so bumping it changes the cache key and the
rebuild actually happens.

Note the container must be *recreated*, not just rebuilt: the toolkit does
`import yt_dlp`, so running gunicorn workers keep the old module in memory.

Files:

- `refresh-ytdlp.sh` — compare running vs PyPI, rebuild + recreate if stale
- `refresh-ytdlp.service` — `oneshot` wrapper for the script
- `refresh-ytdlp.timer` — runs the service weekly (Mondays 04:00)

Config (env, optional):

- `COMPOSE_DIR` — repo root holding `docker-compose.yml` (default: two
  levels up from the script)
- `NCA_CONTAINER` — container name (default `n8n-nca-toolkit`)

The script is a no-op when the running version already matches PyPI, so it
is safe to run by hand at any time.

### Install refresh-ytdlp

```bash
cd deploy/systemd
install -m 0755 refresh-ytdlp.sh ~/scripts/
install -m 0644 refresh-ytdlp.service ~/.config/systemd/user/
install -m 0644 refresh-ytdlp.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now refresh-ytdlp.timer
```
