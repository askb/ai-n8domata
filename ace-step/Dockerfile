# SPDX-License-Identifier: Apache-2.0
# Reuse the box's PROVEN ROCm-7 torch (sadtalker base, torch 2.10+rocm7.2.4).
# Do NOT use rocm/pytorch:rocm6.x — it mismatches the ROCm-7 host.
FROM n8n-autoscaling-ag15-sadtalker
ENV HSA_OVERRIDE_GFX_VERSION=10.3.0 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/* || true
# ACE-Step WITHOUT replacing torch (its deps would pull a non-ROCm torch); deps already
# satisfied by the base + this layer. torchcodec is intentionally absent (save uses soundfile).
RUN pip install --no-cache-dir "git+https://github.com/ace-step/ACE-Step.git" \
      "fastapi" "uvicorn[standard]"
COPY app.py /opt/ace/app.py
EXPOSE 8001
ENTRYPOINT []
CMD ["uvicorn","app:app","--app-dir","/opt/ace","--host","0.0.0.0","--port","8001"]
