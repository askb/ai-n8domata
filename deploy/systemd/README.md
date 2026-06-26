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
