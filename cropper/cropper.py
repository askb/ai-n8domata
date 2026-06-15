import logging
import os
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import unquote, urlparse

import cv2
import mediapipe as mp
import numpy as np
import requests
import uvicorn
from fastapi import FastAPI, HTTPException
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


class SpeakerCropRequest(BaseModel):
    video_path: str
    target_aspect_ratio: str = "9:16"
    sample_fps: float = 4.0
    smoothing_window: int = 7


class CropResponse(BaseModel):
    success: bool
    message: str
    crop_regions: Optional[List[Dict]] = None
    ffmpeg_command: Optional[str] = None
    source_width: Optional[int] = None
    source_height: Optional[int] = None
    fps: Optional[float] = None
    crop_width: Optional[int] = None
    crop_height: Optional[int] = None


class VideoCropper:
    def __init__(self):
        self.face_detection = mp_face_detection.FaceDetection(
            model_selection=1,  # 1 for long-range detection
            min_detection_confidence=0.5,
        )
        # Short-range model (model_selection=0) is better for close-up
        # talking-head framing. Used only by the speaker-tracking path to
        # maximize recall; /analyze keeps using the long-range model above.
        self.face_detection_short = mp_face_detection.FaceDetection(
            model_selection=0,
            min_detection_confidence=0.4,
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
                f"Video downloaded successfully: {temp_path} " f"({file_size} bytes)"
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
                except Exception:
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
                except Exception:
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
            "confidence": len(faces) / 10.0,  # Simple confidence
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
            except Exception:
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

    def detect_faces_scored(
        self, frame: np.ndarray
    ) -> List[Tuple[int, int, int, int, float]]:
        """Detect faces (both MediaPipe models) with detection score.

        Runs the short-range and long-range models and merges results,
        de-duplicating overlapping detections, to maximize recall on varied
        framing. Returns absolute-pixel boxes with score.
        """
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        h, w, _ = frame.shape

        candidates = []
        for model in (self.face_detection_short, self.face_detection):
            results = model.process(rgb_frame)
            if not results.detections:
                continue
            for detection in results.detections:
                bbox = detection.location_data.relative_bounding_box
                x = int(bbox.xmin * w)
                y = int(bbox.ymin * h)
                width = int(bbox.width * w)
                height = int(bbox.height * h)
                if width <= 0 or height <= 0:
                    continue
                score = float(detection.score[0]) if detection.score else 0.5
                candidates.append((x, y, width, height, score))

        # De-duplicate: keep largest first, drop boxes with near-identical center
        deduped: List[Tuple[int, int, int, int, float]] = []
        for face in sorted(candidates, key=lambda f: f[2] * f[3], reverse=True):
            fcx = face[0] + face[2] / 2.0
            fcy = face[1] + face[3] / 2.0
            is_dup = False
            for kept in deduped:
                kcx = kept[0] + kept[2] / 2.0
                kcy = kept[1] + kept[3] / 2.0
                if abs(fcx - kcx) < kept[2] * 0.5 and abs(fcy - kcy) < kept[3] * 0.5:
                    is_dup = True
                    break
            if not is_dup:
                deduped.append(face)

        return deduped

    @staticmethod
    def _pick_dominant_face(
        faces: List[Tuple[int, int, int, int, float]],
        frame_w: int,
        frame_h: int,
    ) -> Optional[Tuple[int, int, int, int, float]]:
        """Pick the active-speaker proxy: largest face, biased toward center.

        Without audio we approximate the active speaker by the face that is
        closest to the camera (largest bounding box), with a mild bias toward
        the frame center so a momentary large background face does not win.
        """
        if not faces:
            return None

        cx_frame = frame_w / 2.0

        def rank(face: Tuple[int, int, int, int, float]) -> float:
            x, _y, w, h, _s = face
            area = float(w * h)
            face_cx = x + w / 2.0
            center_penalty = 1.0 - 0.25 * min(
                1.0, abs(face_cx - cx_frame) / (frame_w / 2.0)
            )
            return area * center_penalty

        return max(faces, key=rank)

    @staticmethod
    def _area(face: Tuple[int, int, int, int, float]) -> float:
        return float(face[2] * face[3])

    def _select_speaker(
        self,
        faces: List[Tuple[int, int, int, int, float]],
        frame_w: int,
        frame_h: int,
        state: Dict,
    ) -> Optional[Tuple[int, int, int, int, float]]:
        """Stateful active-speaker proxy with lock + switch hysteresis.

        The stateless "largest face" proxy flips between people in multi-face
        (interview/panel) shots, so the vertical crop oscillates and often
        frames the wrong (silent) person or the empty gap between them. This
        keeps the crop LOCKED on one face and only switches to a different face
        after that face has stayed clearly larger for a sustained run of
        samples. Brief cutaways are held by the caller's gap-fill instead of
        snapping to whoever is on screen.

        state keys: locked_cx, challenger_cx, challenger_count, switch_hold,
        switch_margin, near_tol.
        """
        if not faces:
            return None

        best = self._pick_dominant_face(faces, frame_w, frame_h)
        locked_cx = state.get("locked_cx")
        if locked_cx is None:
            state["locked_cx"] = best[0] + best[2] / 2.0
            state["challenger_cx"] = None
            state["challenger_count"] = 0
            return best

        near_tol = state["near_tol"]
        # Incumbent = the face nearest the currently locked speaker center.
        incumbent = min(faces, key=lambda f: abs((f[0] + f[2] / 2.0) - locked_cx))
        inc_cx = incumbent[0] + incumbent[2] / 2.0
        present = abs(inc_cx - locked_cx) <= near_tol
        best_cx = best[0] + best[2] / 2.0

        if present:
            # Only a clearly larger, sufficiently different face can challenge.
            challenger = (
                abs(best_cx - inc_cx) > near_tol
                and self._area(best) > self._area(incumbent) * state["switch_margin"]
            )
        else:
            # Locked speaker not visible this sample -> the best face is a
            # re-lock candidate, but still require sustained confirmation.
            challenger = True

        if challenger:
            if state.get("challenger_cx") is not None and (
                abs(best_cx - state["challenger_cx"]) <= near_tol
            ):
                state["challenger_count"] += 1
            else:
                state["challenger_cx"] = best_cx
                state["challenger_count"] = 1
            if state["challenger_count"] >= state["switch_hold"]:
                state["locked_cx"] = best_cx
                state["challenger_cx"] = None
                state["challenger_count"] = 0
                return best
        else:
            state["challenger_cx"] = None
            state["challenger_count"] = 0

        if present:
            # Smoothly follow the locked speaker as they shift in their seat.
            state["locked_cx"] = 0.7 * locked_cx + 0.3 * inc_cx
            return incumbent
        # Locked speaker temporarily gone and no sustained replacement yet;
        # return None so the caller's gap-fill holds the last speaker center.
        return None

    @staticmethod
    def _smooth_centers(centers: List[float], window: int) -> List[float]:
        """Moving-average smoothing of face-center x to reduce jitter."""
        if window < 2 or len(centers) < 2:
            return centers
        half = window // 2
        smoothed = []
        n = len(centers)
        for i in range(n):
            start = max(0, i - half)
            end = min(n, i + half + 1)
            seg = centers[start:end]
            smoothed.append(sum(seg) / len(seg))
        return smoothed

    def analyze_video_speaker(
        self,
        video_path: str,
        target_aspect_ratio: str = "9:16",
        sample_fps: float = 4.0,
        smoothing_window: int = 7,
        **kwargs,
    ) -> Dict:
        """Active-speaker-aware analysis.

        Samples the video at a fixed cadence, locks onto the dominant face per
        sample, and returns a full-height vertical (9:16) crop timeline centered
        on that face. Includes source dimensions so the caller can normalize
        coordinates correctly regardless of source resolution.
        """
        resolved_path = self.resolve_video_path(video_path)
        if not os.path.exists(resolved_path):
            raise FileNotFoundError(f"Video file not found: {resolved_path}")

        cap = cv2.VideoCapture(resolved_path)
        if not cap.isOpened():
            raise ValueError(f"Cannot open video file: {resolved_path}")

        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        if fps <= 0:
            fps = 30.0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        source_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        source_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

        aspect_parts = target_aspect_ratio.split(":")
        try:
            target_ratio = float(aspect_parts[0]) / float(aspect_parts[1])
        except (ValueError, IndexError, ZeroDivisionError):
            target_ratio = 9.0 / 16.0

        crop_w = min(source_w, int(round(source_h * target_ratio)))
        crop_h = source_h
        step = max(1, int(round(fps / max(0.5, sample_fps))))

        logger.info(
            f"[speaker] {source_w}x{source_h} {fps:.2f}fps {total_frames} frames "
            f"step={step} crop={crop_w}x{crop_h}"
        )

        raw = []
        frame_idx = 0
        # Speaker-lock state for hysteresis (see _select_speaker). Requires a
        # different face to stay clearly larger for ~1.2s before the crop
        # switches speakers, which stops the back-and-forth flicker in
        # interview/panel shots.
        track_state = {
            "locked_cx": None,
            "challenger_cx": None,
            "challenger_count": 0,
            "switch_hold": max(2, int(round(1.2 * sample_fps))),
            "switch_margin": 1.20,
            "near_tol": 0.18 * source_w,
        }
        while True:
            grabbed = cap.grab()
            if not grabbed:
                break
            if frame_idx % step == 0:
                ok, frame = cap.retrieve()
                if not ok:
                    break
                faces = self.detect_faces_scored(frame)
                dominant = self._select_speaker(faces, source_w, source_h, track_state)
                if dominant:
                    fx, fy, fw, fh, score = dominant
                    face_cx = fx + fw / 2.0
                    face_cy = fy + fh / 2.0
                    confidence = round(score, 3)
                else:
                    face_cx = source_w / 2.0
                    face_cy = source_h / 2.0
                    confidence = 0.0
                raw.append(
                    [
                        frame_idx,
                        frame_idx / fps,
                        face_cx,
                        face_cy,
                        confidence,
                        len(faces),
                    ]
                )
            frame_idx += 1

        cap.release()

        if video_path.startswith("http") and os.path.exists(resolved_path):
            try:
                os.remove(resolved_path)
                logger.info(f"Cleaned up temporary file: {resolved_path}")
            except Exception:
                pass

        # Gap-fill: hold the last confident face center across short detection
        # gaps instead of snapping to frame center. Keeps the crop locked on the
        # speaker when MediaPipe momentarily loses the face between samples.
        hold_samples = max(1, int(round(2.0 * fps / step)))
        center_default = source_w / 2.0
        filled_centers = [center_default] * len(raw)
        tracked_flags = [False] * len(raw)
        last_valid_cx = None
        last_valid_i = None
        for i, r in enumerate(raw):
            has_face = r[5] > 0 and r[4] >= 0.3
            if has_face:
                filled_centers[i] = r[2]
                tracked_flags[i] = True
                last_valid_cx = r[2]
                last_valid_i = i
            elif last_valid_cx is not None and (i - last_valid_i) <= hold_samples:
                filled_centers[i] = last_valid_cx
                tracked_flags[i] = True
        # Back-fill the leading gap (before the first detection) so the clip
        # opens already framed on the speaker rather than dead center.
        first_valid = next((i for i, t in enumerate(tracked_flags) if t), None)
        if first_valid:
            for i in range(first_valid):
                filled_centers[i] = filled_centers[first_valid]

        centers = self._smooth_centers(filled_centers, smoothing_window)

        crop_regions = []
        max_x = max(0, source_w - crop_w)
        for r, smooth_cx, tracked in zip(raw, centers, tracked_flags):
            frame_no, timestamp, _cx, face_cy, confidence, num_faces = r
            crop_x = int(round(min(max(smooth_cx - crop_w / 2.0, 0), max_x)))
            crop_regions.append(
                {
                    "frame": frame_no,
                    "timestamp": round(timestamp, 3),
                    "x": crop_x,
                    "y": 0,
                    "width": crop_w,
                    "height": crop_h,
                    "face_cx": round(smooth_cx, 1),
                    "face_cy": round(face_cy, 1),
                    "num_faces": num_faces,
                    "confidence": confidence,
                    "tracked": tracked,
                }
            )

        return {
            "total_frames": total_frames,
            "fps": fps,
            "source_width": source_w,
            "source_height": source_h,
            "crop_width": crop_w,
            "crop_height": crop_h,
            "target_aspect_ratio": target_aspect_ratio,
            "crop_regions": crop_regions,
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
        # Video path will be resolved inside analyze_video
        # (handles URLs and local paths)
        result = cropper.analyze_video(
            video_path=request.video_path,
            target_aspect_ratio=request.target_aspect_ratio,
            padding_factor=request.padding_factor,
            smoothing_window=request.smoothing_window,
        )

        return CropResponse(
            success=True,
            message=(f"Analysis complete: {result['total_frames']} frames processed"),
            crop_regions=result["crop_regions"],
        )

    except Exception as e:
        logger.error(f"Analysis failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/crop", response_model=CropResponse)
async def crop_video(request: CropRequest):
    """Analyze video and generate FFmpeg command for cropping"""
    try:
        # Video path will be resolved inside analyze_video
        # (handles URLs and local paths)
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
            message=(
                "Crop analysis complete. Use the FFmpeg command to "
                "process the video."
            ),
            crop_regions=result["crop_regions"],
            ffmpeg_command=ffmpeg_cmd,
        )

    except Exception as e:
        logger.error(f"Crop analysis failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/analyze_speaker", response_model=CropResponse)
async def analyze_speaker(request: SpeakerCropRequest):
    """Active-speaker-aware analysis returning a dynamic vertical crop timeline.

    Unlike /analyze (which boxes all faces into one region), this locks onto the
    dominant face per sample so the caller can pan the crop to follow the speaker.
    """
    try:
        result = cropper.analyze_video_speaker(
            video_path=request.video_path,
            target_aspect_ratio=request.target_aspect_ratio,
            sample_fps=request.sample_fps,
            smoothing_window=request.smoothing_window,
        )

        return CropResponse(
            success=True,
            message=(
                f"Speaker analysis complete: {len(result['crop_regions'])} "
                f"samples over {result['total_frames']} frames"
            ),
            crop_regions=result["crop_regions"],
            source_width=result["source_width"],
            source_height=result["source_height"],
            fps=result["fps"],
            crop_width=result["crop_width"],
            crop_height=result["crop_height"],
        )

    except Exception as e:
        logger.error(f"Speaker analysis failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8888)
