import json
import logging
import os
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import unquote, urlparse

import cv2
import mediapipe as mp
import numpy as np
import requests
import uvicorn
from fastapi import BackgroundTasks, FastAPI, HTTPException
from pydantic import BaseModel

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Intelligent Video Cropper", version="1.0.0")

# Initialize MediaPipe
mp_face_detection = mp.solutions.face_detection
mp_drawing = mp.solutions.drawing_utils


class CropRequest(BaseModel):
    video_path: str
    output_path: Optional[str] = None
    target_aspect_ratio: str = "16:9"
    padding_factor: float = 0.2
    smoothing_window: int = 5


class CropResponse(BaseModel):
    success: bool
    message: str
    crop_regions: Optional[List[Dict]] = None
    ffmpeg_command: Optional[str] = None


class VideoCropper:
    def __init__(self):
        self.face_detection = mp_face_detection.FaceDetection(
            model_selection=1,  # 1 for long-range detection
            min_detection_confidence=0.5,
        )

    def download_video(self, url: str) -> str:
        """Download video from URL to temporary file"""
        try:
            logger.info(f"Downloading video from: {url}")

            # Create temp file with proper name handling
            temp_dir = "/tmp"
            os.makedirs(temp_dir, exist_ok=True)

            # Get filename from URL and decode it properly
            parsed_url = urlparse(url)
            filename = (
                unquote(os.path.basename(parsed_url.path)) or "downloaded_video.mp4"
            )

            # Clean filename - remove problematic characters
            filename = "".join(
                c for c in filename if c.isalnum() or c in (" ", "-", "_", ".")
            )
            if not filename.endswith(".mp4"):
                filename += ".mp4"

            temp_path = os.path.join(temp_dir, filename)

            logger.info(f"Downloading to: {temp_path}")

            # Download the file with better error handling
            response = requests.get(url, stream=True, timeout=30)
            response.raise_for_status()

            # Check if we got a valid response
            if response.status_code != 200:
                raise ValueError(f"HTTP {response.status_code} error downloading video")

            # Check content type
            content_type = response.headers.get("content-type", "")
            if not any(
                video_type in content_type.lower()
                for video_type in ["video/", "application/octet-stream"]
            ):
                logger.warning(f"Unexpected content type: {content_type}")

            # Download with progress tracking
            total_size = int(response.headers.get("content-length", 0))
            downloaded = 0

            with open(temp_path, "wb") as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)

                        # Log progress for large files
                        if (
                            total_size > 0 and downloaded % (1024 * 1024) == 0
                        ):  # Every MB
                            progress = (downloaded / total_size) * 100
                            logger.info(f"Download progress: {progress:.1f}%")

            # Verify file exists and has content
            if not os.path.exists(temp_path):
                raise ValueError("Downloaded file does not exist")

            file_size = os.path.getsize(temp_path)
            if file_size == 0:
                raise ValueError("Downloaded file is empty")

            logger.info(
                f"Video downloaded successfully: {temp_path} ({file_size} bytes)"
            )

            # Quick test that OpenCV can open the file
            test_cap = cv2.VideoCapture(temp_path)
            if not test_cap.isOpened():
                test_cap.release()
                # Try to get more info about the file
                try:
                    with open(temp_path, "rb") as f:
                        header = f.read(12)
                        logger.error(f"File header: {header}")
                except:
                    pass
                raise ValueError("OpenCV cannot open the downloaded video file")

            # Get basic video info
            frame_count = int(test_cap.get(cv2.CAP_PROP_FRAME_COUNT))
            fps = test_cap.get(cv2.CAP_PROP_FPS)
            test_cap.release()

            logger.info(f"Video info: {frame_count} frames at {fps} FPS")

            return temp_path

        except requests.exceptions.RequestException as e:
            logger.error(f"Request failed: {str(e)}")
            raise ValueError(f"Failed to download video from {url}: {str(e)}")
        except Exception as e:
            logger.error(f"Download failed: {str(e)}")
            # Clean up partial file
            if "temp_path" in locals() and os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except:
                    pass
            raise ValueError(f"Could not download video from {url}: {str(e)}")

    def resolve_video_path(self, video_path: str) -> str:
        """Resolve video path - download if URL, return local path if file"""
        if video_path.startswith("http://") or video_path.startswith("https://"):
            # It's a URL, download it
            return self.download_video(video_path)
        elif not video_path.startswith("/"):
            # It's a relative path, make it absolute
            return f"/app/videos/{video_path}"
        else:
            # It's already an absolute path
            return video_path

    def detect_faces_in_frame(
        self, frame: np.ndarray
    ) -> List[Tuple[int, int, int, int]]:
        """Detect faces in a frame and return bounding boxes"""
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = self.face_detection.process(rgb_frame)

        faces = []
        if results.detections:
            for detection in results.detections:
                bbox = detection.location_data.relative_bounding_box
                h, w, _ = frame.shape

                # Convert relative coordinates to absolute
                x = int(bbox.xmin * w)
                y = int(bbox.ymin * h)
                width = int(bbox.width * w)
                height = int(bbox.height * h)

                faces.append((x, y, width, height))

        return faces

    def calculate_crop_region(
        self,
        faces: List[Tuple[int, int, int, int]],
        frame_shape: Tuple[int, int],
        target_aspect_ratio: str = "16:9",
        padding_factor: float = 0.2,
    ) -> Dict:
        """Calculate optimal crop region based on detected faces"""
        h, w = frame_shape[:2]

        # Parse target aspect ratio
        aspect_parts = target_aspect_ratio.split(":")
        target_ratio = float(aspect_parts[0]) / float(aspect_parts[1])

        if not faces:
            # No faces detected, return center crop
            crop_w = int(h * target_ratio)
            crop_h = h
            if crop_w > w:
                crop_w = w
                crop_h = int(w / target_ratio)

            crop_x = (w - crop_w) // 2
            crop_y = (h - crop_h) // 2

            return {
                "x": crop_x,
                "y": crop_y,
                "width": crop_w,
                "height": crop_h,
                "confidence": 0.0,
            }

        # Find bounding box that contains all faces
        min_x = min(face[0] for face in faces)
        min_y = min(face[1] for face in faces)
        max_x = max(face[0] + face[2] for face in faces)
        max_y = max(face[1] + face[3] for face in faces)

        # Add padding
        content_w = max_x - min_x
        content_h = max_y - min_y

        pad_w = int(content_w * padding_factor)
        pad_h = int(content_h * padding_factor)

        # Expand region with padding
        crop_x = max(0, min_x - pad_w)
        crop_y = max(0, min_y - pad_h)
        crop_w = min(w - crop_x, content_w + 2 * pad_w)
        crop_h = min(h - crop_y, content_h + 2 * pad_h)

        # Adjust to target aspect ratio
        current_ratio = crop_w / crop_h

        if current_ratio > target_ratio:
            # Too wide, adjust height
            new_h = int(crop_w / target_ratio)
            if crop_y + new_h <= h:
                crop_h = new_h
            else:
                crop_h = h - crop_y
                crop_w = int(crop_h * target_ratio)
        else:
            # Too tall, adjust width
            new_w = int(crop_h * target_ratio)
            if crop_x + new_w <= w:
                crop_w = new_w
            else:
                crop_w = w - crop_x
                crop_h = int(crop_w / target_ratio)

        return {
            "x": crop_x,
            "y": crop_y,
            "width": crop_w,
            "height": crop_h,
            "confidence": len(faces) / 10.0,  # Simple confidence based on face count
        }

    def smooth_crop_regions(
        self, regions: List[Dict], window_size: int = 5
    ) -> List[Dict]:
        """Apply temporal smoothing to crop regions"""
        if len(regions) < window_size:
            return regions

        smoothed = []
        for i in range(len(regions)):
            start_idx = max(0, i - window_size // 2)
            end_idx = min(len(regions), i + window_size // 2 + 1)

            window_regions = regions[start_idx:end_idx]

            # Average the coordinates
            avg_x = sum(r["x"] for r in window_regions) // len(window_regions)
            avg_y = sum(r["y"] for r in window_regions) // len(window_regions)
            avg_w = sum(r["width"] for r in window_regions) // len(window_regions)
            avg_h = sum(r["height"] for r in window_regions) // len(window_regions)

            smoothed.append(
                {
                    "x": avg_x,
                    "y": avg_y,
                    "width": avg_w,
                    "height": avg_h,
                    "confidence": regions[i]["confidence"],
                }
            )

        return smoothed

    def analyze_video(self, video_path: str, **kwargs) -> Dict:
        """Analyze video and return crop regions for each frame"""
        # Resolve video path (download if URL)
        resolved_path = self.resolve_video_path(video_path)

        if not os.path.exists(resolved_path):
            raise FileNotFoundError(f"Video file not found: {resolved_path}")

        cap = cv2.VideoCapture(resolved_path)
        if not cap.isOpened():
            raise ValueError(f"Cannot open video file: {resolved_path}")

        frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = cap.get(cv2.CAP_PROP_FPS)

        logger.info(f"Analyzing video: {frame_count} frames at {fps} FPS")

        crop_regions = []
        frame_idx = 0

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            # Detect faces
            faces = self.detect_faces_in_frame(frame)

            # Calculate crop region
            crop_region = self.calculate_crop_region(
                faces,
                frame.shape,
                kwargs.get("target_aspect_ratio", "16:9"),
                kwargs.get("padding_factor", 0.2),
            )

            crop_region["frame"] = frame_idx
            crop_region["timestamp"] = frame_idx / fps
            crop_regions.append(crop_region)

            frame_idx += 1

            if frame_idx % 100 == 0:
                logger.info(f"Processed {frame_idx}/{frame_count} frames")

        cap.release()

        # Clean up temporary file if we downloaded one
        if video_path.startswith("http") and os.path.exists(resolved_path):
            try:
                os.remove(resolved_path)
                logger.info(f"Cleaned up temporary file: {resolved_path}")
            except:
                pass

        # Apply smoothing
        smoothed_regions = self.smooth_crop_regions(
            crop_regions, kwargs.get("smoothing_window", 5)
        )

        return {
            "total_frames": frame_count,
            "fps": fps,
            "crop_regions": smoothed_regions,
            "original_path": video_path,
            "resolved_path": resolved_path,
        }

    def generate_ffmpeg_command(
        self, video_path: str, crop_regions: List[Dict], output_path: str
    ) -> str:
        """Generate FFmpeg command for dynamic cropping"""

        # For simplicity, use the most common crop region
        # In production, you'd want to implement keyframe-based cropping
        if not crop_regions:
            return f'ffmpeg -i "{video_path}" -c copy "{output_path}"'

        # Calculate average crop region
        avg_x = sum(r["x"] for r in crop_regions) // len(crop_regions)
        avg_y = sum(r["y"] for r in crop_regions) // len(crop_regions)
        avg_w = sum(r["width"] for r in crop_regions) // len(crop_regions)
        avg_h = sum(r["height"] for r in crop_regions) // len(crop_regions)

        # Ensure even dimensions (required by many codecs)
        avg_w = avg_w - (avg_w % 2)
        avg_h = avg_h - (avg_h % 2)

        ffmpeg_cmd = (
            f'ffmpeg -i "{video_path}" '
            f'-vf "crop={avg_w}:{avg_h}:{avg_x}:{avg_y}" '
            f'-c:a copy "{output_path}"'
        )

        return ffmpeg_cmd


# Initialize cropper
cropper = VideoCropper()


@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "intelligent-cropper"}


@app.post("/analyze", response_model=CropResponse)
async def analyze_video(request: CropRequest):
    """Analyze video and return crop regions"""
    try:
        # Video path will be resolved inside analyze_video (handles URLs and local paths)
        result = cropper.analyze_video(
            video_path=request.video_path,
            target_aspect_ratio=request.target_aspect_ratio,
            padding_factor=request.padding_factor,
            smoothing_window=request.smoothing_window,
        )

        return CropResponse(
            success=True,
            message=f"Analysis complete: {result['total_frames']} frames processed",
            crop_regions=result["crop_regions"],
        )

    except Exception as e:
        logger.error(f"Analysis failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/crop", response_model=CropResponse)
async def crop_video(request: CropRequest):
    """Analyze video and generate FFmpeg command for cropping"""
    try:
        # Video path will be resolved inside analyze_video (handles URLs and local paths)
        video_path = request.video_path

        output_path = request.output_path
        if not output_path:
            # Generate output path based on input
            if video_path.startswith("http"):
                parsed_url = urlparse(video_path)
                base_name = (
                    os.path.splitext(os.path.basename(parsed_url.path))[0] or "video"
                )
            else:
                base_name = Path(video_path).stem
            output_path = f"/app/videos/{base_name}_cropped.mp4"
        elif not output_path.startswith("/"):
            output_path = f"/app/videos/{output_path}"

        # Analyze video
        result = cropper.analyze_video(
            video_path=video_path,
            target_aspect_ratio=request.target_aspect_ratio,
            padding_factor=request.padding_factor,
            smoothing_window=request.smoothing_window,
        )

        # Generate FFmpeg command
        ffmpeg_cmd = cropper.generate_ffmpeg_command(
            video_path, result["crop_regions"], output_path
        )

        return CropResponse(
            success=True,
            message=f"Crop analysis complete. Use the FFmpeg command to process the video.",
            crop_regions=result["crop_regions"],
            ffmpeg_command=ffmpeg_cmd,
        )

    except Exception as e:
        logger.error(f"Crop analysis failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8888)
