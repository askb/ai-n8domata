import asyncio
import os
import shutil
import subprocess
import uuid
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from starlette.background import BackgroundTask

SADTALKER_ROOT = Path(os.environ.get("SADTALKER_ROOT", "/opt/SadTalker"))
WORK_DIR = Path(os.environ.get("SADTALKER_WORK_DIR", "/workspace")) / "jobs"
DEFAULT_PREPROCESS = os.environ.get("SADTALKER_PREPROCESS", "full")
DEFAULT_SIZE = os.environ.get("SADTALKER_SIZE", "256")
DEFAULT_STILL = os.environ.get("SADTALKER_STILL", "true").lower() == "true"
DEFAULT_ENHANCER = os.environ.get("SADTALKER_ENHANCER", "").strip()

app = FastAPI(title="SadTalker Service", version="1.0.0")
_gpu_lock = asyncio.Lock()


def _suffix(filename: str | None, fallback: str) -> str:
    suffix = Path(filename or "").suffix.lower()
    return suffix if suffix else fallback


def _cleanup(path: Path) -> None:
    shutil.rmtree(path, ignore_errors=True)


@app.get("/health")
def health() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.post("/api/talk")
async def talk(image: UploadFile = File(...), audio: UploadFile = File(...)) -> FileResponse:
    job_dir = WORK_DIR / str(uuid.uuid4())
    input_dir = job_dir / "input"
    result_dir = job_dir / "result"
    input_dir.mkdir(parents=True, exist_ok=True)
    result_dir.mkdir(parents=True, exist_ok=True)

    image_path = input_dir / f"source{_suffix(image.filename, '.png')}"
    audio_path = input_dir / f"driven{_suffix(audio.filename, '.wav')}"

    try:
        with image_path.open("wb") as fh:
            shutil.copyfileobj(image.file, fh)
        with audio_path.open("wb") as fh:
            shutil.copyfileobj(audio.file, fh)

        cmd = [
            "python",
            "inference.py",
            "--driven_audio",
            str(audio_path),
            "--source_image",
            str(image_path),
            "--result_dir",
            str(result_dir),
            "--preprocess",
            DEFAULT_PREPROCESS,
            "--size",
            DEFAULT_SIZE,
        ]
        if DEFAULT_STILL:
            cmd.append("--still")
        if DEFAULT_ENHANCER:
            cmd.extend(["--enhancer", DEFAULT_ENHANCER])

        async with _gpu_lock:
            proc = await asyncio.to_thread(
                subprocess.run,
                cmd,
                cwd=SADTALKER_ROOT,
                text=True,
                capture_output=True,
                timeout=int(os.environ.get("SADTALKER_TIMEOUT_SECONDS", "900")),
                check=False,
            )

        if proc.returncode != 0:
            raise HTTPException(
                status_code=500,
                detail={
                    "error": "SadTalker inference failed",
                    "returncode": proc.returncode,
                    "stderr": proc.stderr[-4000:],
                    "stdout": proc.stdout[-2000:],
                },
            )

        mp4s = sorted(result_dir.rglob("*.mp4"), key=lambda p: p.stat().st_mtime, reverse=True)
        if not mp4s:
            raise HTTPException(
                status_code=500,
                detail={
                    "error": "SadTalker completed but produced no mp4",
                    "stdout": proc.stdout[-2000:],
                },
            )

        return FileResponse(
            mp4s[0],
            media_type="video/mp4",
            filename="sadtalker.mp4",
            background=BackgroundTask(_cleanup, job_dir),
        )
    except HTTPException:
        _cleanup(job_dir)
        raise
    except subprocess.TimeoutExpired as exc:
        _cleanup(job_dir)
        raise HTTPException(status_code=504, detail=f"SadTalker timed out: {exc}") from exc
    except Exception as exc:
        _cleanup(job_dir)
        raise HTTPException(status_code=500, detail=str(exc)) from exc
