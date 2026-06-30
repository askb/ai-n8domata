# SPDX-License-Identifier: Apache-2.0
# ACE-Step music-gen service for the ai-n8domata stack (AMD ROCm).
# n8n calls /generate; n8n never touches ACE-Step internals (SUL-compliant).
import os, time, uuid, subprocess
# --- save shim: torchaudio 2.10 routes save->torchcodec (ABI-incompatible with the
#     custom ROCm torch). Force soundfile instead. ---
import torchaudio, soundfile as sf
def _save(uri, src, sample_rate=44100, *a, **k):
    arr = src.detach().cpu().float().numpy()
    if arr.ndim == 2:
        arr = arr.T
    sf.write(uri, arr, int(sample_rate))
torchaudio.save = _save

from fastapi import FastAPI
from pydantic import BaseModel
from acestep.pipeline_ace_step import ACEStepPipeline

OUT = os.environ.get("OUT_DIR", "/out")
os.makedirs(OUT, exist_ok=True)
_pipe = None
def pipe():
    global _pipe
    if _pipe is None:
        _pipe = ACEStepPipeline(
            checkpoint_dir=os.environ.get("ACE_CKPT", "/root/.cache/ace-step/checkpoints"),
            device_id=int(os.environ.get("ACE_DEVICE", "0")),
            dtype="bfloat16", cpu_offload=False, overlapped_decode=False, torch_compile=False)
    return _pipe

app = FastAPI()

class Req(BaseModel):
    prompt: str
    duration: float = 30.0
    infer_step: int = 27
    seed: int | None = None
    mp3: bool = True
    ref_path: str | None = None        # audio2audio style reference (mounted file in /out or /ref)
    ref_strength: float = 0.5          # 0=ignore ref, 1=clone ref

@app.get("/health")
def health():
    return {"ok": True}

@app.post("/generate")
def generate(r: Req):
    t0 = time.time()
    base = f"track_{uuid.uuid4().hex[:10]}"
    wav = f"{OUT}/{base}.wav"
    extra = {}
    if r.ref_path:
        extra = dict(audio2audio_enable=True, ref_audio_input=r.ref_path, ref_audio_strength=r.ref_strength)
    pipe()(format="wav", audio_duration=r.duration, prompt=r.prompt, lyrics="[inst]",
           infer_step=r.infer_step, save_path=wav, batch_size=1,
           manual_seeds=[r.seed] if r.seed is not None else None, **extra)
    out = wav
    if r.mp3:
        out = f"{OUT}/{base}.mp3"
        subprocess.run(["ffmpeg", "-y", "-i", wav, "-b:a", "192k", out],
                       check=True, capture_output=True)
    return {"file": out, "seconds": round(time.time() - t0, 1)}
