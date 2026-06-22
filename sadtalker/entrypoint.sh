#!/usr/bin/env bash
set -euo pipefail

SADTALKER_ROOT="${SADTALKER_ROOT:-/opt/SadTalker}"
MODEL_DIR="${SADTALKER_MODEL_DIR:-/models}"
WORK_DIR="${SADTALKER_WORK_DIR:-/workspace}"

mkdir -p "${MODEL_DIR}/checkpoints" "${MODEL_DIR}/gfpgan/weights" "${WORK_DIR}/jobs"

rm -rf "${SADTALKER_ROOT}/checkpoints"
ln -s "${MODEL_DIR}/checkpoints" "${SADTALKER_ROOT}/checkpoints"
mkdir -p "${SADTALKER_ROOT}/gfpgan"
rm -rf "${SADTALKER_ROOT}/gfpgan/weights"
ln -s "${MODEL_DIR}/gfpgan/weights" "${SADTALKER_ROOT}/gfpgan/weights"

if [ ! -f "${MODEL_DIR}/checkpoints/SadTalker_V0.0.2_256.safetensors" ] && \
   [ ! -f "${MODEL_DIR}/checkpoints/SadTalker_V0.0.2_512.safetensors" ]; then
    echo "SadTalker checkpoints not found in ${MODEL_DIR}; downloading once into the model volume..."
    cd "${SADTALKER_ROOT}"
    bash scripts/download_models.sh
fi

# Patch (idempotent): face-renderer offloads each frame to CPU so it doesn't
# accumulate all frames in VRAM and OOM at ~85% on ~30s clips (12GB GPU).
# (The compose bind-mount also provides this; the sed makes a rebuild robust.)
sed -i "s/predictions.append(out\['prediction'\])/predictions.append(out['prediction'].cpu())/" \
    "${SADTALKER_ROOT}/src/facerender/modules/make_animation.py" || true

cd /app
exec uvicorn app:app --host 0.0.0.0 --port 7860 --timeout-keep-alive 120
