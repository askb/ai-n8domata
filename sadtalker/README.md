# SadTalker Service

GPU-accelerated SadTalker talking-head API for the n8n internal network.
It accepts a single face image plus audio and returns an MP4 with lip sync,
eye blinks, and head motion.

## API

Internal endpoint: `http://sadtalker:7860/api/talk`

```bash
curl -f -X POST http://sadtalker:7860/api/talk \
  -F image=@avatar.png \
  -F audio=@speech.wav \
  --output result.mp4
```

Health check:

```bash
curl -f http://sadtalker:7860/health
```

## ROCm / GPU Notes

The service uses `rocm/pytorch:latest` with `/dev/kfd` and `/dev/dri` passed
through from the Fedora host. The RX 6800M reports as `gfx1030`;
`HSA_OVERRIDE_GFX_VERSION=10.3.0` is set in the service to avoid a ROCm
segfault observed during SadTalker 3DMM extraction.

Verify ROCm inside the container:

```bash
docker exec sadtalker python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

## Operations

Only operate on this service; do not recreate the full n8n stack.

```bash
cd /data/n8n/ai-automata
docker compose config -q
docker compose build sadtalker
docker compose up -d sadtalker
```

Restart only this service:

```bash
cd /data/n8n/ai-automata
docker compose up -d sadtalker
```

## Model Volume

Model checkpoints are downloaded on first container start into the named Docker
volume `n8n-autoscaling-ag15_sadtalker_models`, mounted at `/models`. Do not
commit downloaded weights.

## Validation

The cartoon avatar `ab-world-news/avatar/askb_anchor.png` was accepted and
produced an MP4 test render uploaded to:

`https://miniio.askb.dev/ab-world-news/avatar/test/sadtalker_cartoon.mp4`
