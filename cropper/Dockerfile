FROM python:3.9-slim

WORKDIR /app

# Install system dependencies for OpenCV
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libglib2.0-0 \
    libgtk-3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    mediapipe==0.10.9 \
    opencv-python==4.8.1.78 \
    fastapi==0.104.1 \
    uvicorn==0.24.0 \
    pydantic==2.5.2 \
    requests==2.31.0

# Copy the application
COPY cropper/cropper.py .

# Create videos directory
RUN mkdir -p /app/videos

# Expose port
EXPOSE 8888

# Run the application
CMD ["uvicorn", "cropper:app", "--host", "0.0.0.0", "--port", "8888"]
