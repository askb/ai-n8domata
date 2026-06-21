FROM rocm/pytorch:latest

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    SADTALKER_ROOT=/opt/SadTalker \
    SADTALKER_MODEL_DIR=/models \
    SADTALKER_WORK_DIR=/workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      ffmpeg \
      git \
      libglib2.0-0 \
      libgl1 \
      wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone --depth 1 https://github.com/OpenTalker/SadTalker.git "$SADTALKER_ROOT" \
    && python - <<'PYSRCFIX'
from pathlib import Path
for path in Path('/opt/SadTalker/src').rglob('*.py'):
    text = path.read_text()
    text = text.replace('np.float,', 'float,').replace('np.int,', 'int,')
    text = text.replace('np.float)', 'float)').replace('np.int)', 'int)')
    text = text.replace('trans_params = np.array([w0, h0, s, t[0], t[1]])', "trans_params = np.array([w0, h0, float(np.asarray(s).squeeze()), float(np.asarray(t[0]).squeeze()), float(np.asarray(t[1]).squeeze())])")
    path.write_text(text)
PYSRCFIX

COPY requirements-service.txt /app/requirements-service.txt
WORKDIR /opt/SadTalker
RUN python -m pip install --upgrade pip setuptools wheel \
    && python -m pip install -r /app/requirements-service.txt \
    && python - <<'PYFIX'
from pathlib import Path
for path in Path('/opt/venv/lib/python3.12/site-packages/basicsr').rglob('*.py'):
    text = path.read_text()
    text = text.replace('torchvision.transforms.functional_tensor import rgb_to_grayscale', 'torchvision.transforms.functional import rgb_to_grayscale')
    path.write_text(text)
PYFIX

COPY app.py /app/app.py
COPY entrypoint.sh /usr/local/bin/sadtalker-entrypoint.sh
RUN chmod +x /usr/local/bin/sadtalker-entrypoint.sh \
    && mkdir -p "$SADTALKER_MODEL_DIR" "$SADTALKER_WORK_DIR"

WORKDIR /app
EXPOSE 7860
ENTRYPOINT ["/usr/local/bin/sadtalker-entrypoint.sh"]
