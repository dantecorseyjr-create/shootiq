"""MediaPipe Pose detection + skeleton overlay video for ShootIQ (Step 4)."""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

import cv2
import mediapipe as mp
import numpy as np

# MediaPipe Pose landmark indices
NOSE = 0
LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_ELBOW = 13
RIGHT_ELBOW = 14
LEFT_WRIST = 15
RIGHT_WRIST = 16
LEFT_HIP = 23
RIGHT_HIP = 24
LEFT_KNEE = 25
RIGHT_KNEE = 26
LEFT_ANKLE = 27
RIGHT_ANKLE = 28

TRACKED_LANDMARKS = {
    "nose": NOSE,
    "left_shoulder": LEFT_SHOULDER,
    "right_shoulder": RIGHT_SHOULDER,
    "left_elbow": LEFT_ELBOW,
    "right_elbow": RIGHT_ELBOW,
    "left_wrist": LEFT_WRIST,
    "right_wrist": RIGHT_WRIST,
    "left_hip": LEFT_HIP,
    "right_hip": RIGHT_HIP,
    "left_knee": LEFT_KNEE,
    "right_knee": RIGHT_KNEE,
    "left_ankle": LEFT_ANKLE,
    "right_ankle": RIGHT_ANKLE,
}

BASE_DIR = Path(__file__).resolve().parent
PROCESSED_VIDEOS_DIR = BASE_DIR / "processed_videos"

# BGR colors for form quality overlay.
_STATUS_BGR = {
    "PASS": (60, 200, 80),       # green
    "NEEDS_WORK": (40, 200, 240),  # yellow
    "FAIL": (50, 50, 230),       # red
}

# MediaPipe Pose connection pairs → logical body segment for coloring.
_COLORED_CONNECTIONS: list[tuple[int, int, str]] = [
    (11, 13, "elbow"),   # left shoulder–elbow
    (13, 15, "elbow"),   # left elbow–wrist
    (12, 14, "elbow"),   # right shoulder–elbow
    (14, 16, "elbow"),   # right elbow–wrist
    (23, 25, "knee"),    # left hip–knee
    (25, 27, "knee"),    # left knee–ankle
    (24, 26, "knee"),    # right hip–knee
    (26, 28, "knee"),    # right knee–ankle
    (11, 12, "torso"),   # shoulders
    (23, 24, "torso"),   # hips
    (11, 23, "torso"),   # left torso
    (12, 24, "torso"),   # right torso
]

_COLORED_JOINTS: list[tuple[int, str]] = [
    (0, "torso"),   # nose
    (11, "shoulder"),
    (12, "shoulder"),
    (13, "elbow"),
    (14, "elbow"),
    (15, "wrist"),
    (16, "wrist"),
    (23, "hip"),
    (24, "hip"),
    (25, "knee"),
    (26, "knee"),
    (27, "ankle"),
    (28, "ankle"),
]


_NAMED_CONNECTIONS: list[tuple[str, str, str]] = [
    ("left_shoulder", "left_elbow", "elbow"),
    ("left_elbow", "left_wrist", "elbow"),
    ("right_shoulder", "right_elbow", "elbow"),
    ("right_elbow", "right_wrist", "elbow"),
    ("left_hip", "left_knee", "knee"),
    ("left_knee", "left_ankle", "knee"),
    ("right_hip", "right_knee", "knee"),
    ("right_knee", "right_ankle", "knee"),
    ("left_shoulder", "right_shoulder", "torso"),
    ("left_hip", "right_hip", "torso"),
    ("left_shoulder", "left_hip", "torso"),
    ("right_shoulder", "right_hip", "torso"),
    ("nose", "left_shoulder", "torso"),
    ("nose", "right_shoulder", "torso"),
]

_NAMED_JOINTS: list[tuple[str, str]] = [
    ("nose", "torso"),
    ("left_shoulder", "shoulder"),
    ("right_shoulder", "shoulder"),
    ("left_elbow", "elbow"),
    ("right_elbow", "elbow"),
    ("left_wrist", "wrist"),
    ("right_wrist", "wrist"),
    ("left_hip", "hip"),
    ("right_hip", "hip"),
    ("left_knee", "knee"),
    ("right_knee", "knee"),
    ("left_ankle", "ankle"),
    ("right_ankle", "ankle"),
]


def _draw_colored_skeleton(
    frame: np.ndarray,
    pose_landmarks: Any,
    status: dict[str, str],
) -> None:
    """Draw green / yellow / red skeleton based on per-frame form status."""
    h, w = frame.shape[:2]
    lms = pose_landmarks.landmark

    def pt(index: int) -> tuple[int, int]:
        return int(lms[index].x * w), int(lms[index].y * h)

    for a, b, key in _COLORED_CONNECTIONS:
        color = _STATUS_BGR.get(status.get(key, "PASS"), _STATUS_BGR["PASS"])
        cv2.line(frame, pt(a), pt(b), color, 3, lineType=cv2.LINE_AA)

    for index, key in _COLORED_JOINTS:
        color = _STATUS_BGR.get(status.get(key, "PASS"), _STATUS_BGR["PASS"])
        cv2.circle(frame, pt(index), 6, color, -1, lineType=cv2.LINE_AA)
        cv2.circle(frame, pt(index), 7, (255, 255, 255), 1, lineType=cv2.LINE_AA)


def _draw_colored_skeleton_from_sample(
    frame: np.ndarray,
    sample: dict[str, dict[str, float]],
    status: dict[str, str],
) -> None:
    """Draw skeleton from stored landmark sample (for non-sampled frames)."""
    h, w = frame.shape[:2]

    def pt(name: str) -> tuple[int, int] | None:
        point = sample.get(name)
        if not point:
            return None
        return int(point["x"] * w), int(point["y"] * h)

    for a, b, key in _NAMED_CONNECTIONS:
        pa, pb = pt(a), pt(b)
        if pa is None or pb is None:
            continue
        color = _STATUS_BGR.get(status.get(key, "PASS"), _STATUS_BGR["PASS"])
        cv2.line(frame, pa, pb, color, 3, lineType=cv2.LINE_AA)

    for name, key in _NAMED_JOINTS:
        p = pt(name)
        if p is None:
            continue
        color = _STATUS_BGR.get(status.get(key, "PASS"), _STATUS_BGR["PASS"])
        cv2.circle(frame, p, 6, color, -1, lineType=cv2.LINE_AA)
        cv2.circle(frame, p, 7, (255, 255, 255), 1, lineType=cv2.LINE_AA)


def _extract_landmarks(pose_landmarks: Any) -> dict[str, dict[str, float]]:
    """Pull tracked x/y (and visibility) from a MediaPipe pose result."""
    points: dict[str, dict[str, float]] = {}
    for name, index in TRACKED_LANDMARKS.items():
        lm = pose_landmarks.landmark[index]
        points[name] = {
            "x": float(lm.x),
            "y": float(lm.y),
            "visibility": float(lm.visibility),
        }
    return points


def _average_landmarks(
    samples: list[dict[str, dict[str, float]]],
) -> dict[str, dict[str, float]]:
    """Average landmark x/y across all frames where a pose was detected."""
    if not samples:
        return {name: {"x": 0.0, "y": 0.0} for name in TRACKED_LANDMARKS}

    averaged: dict[str, dict[str, float]] = {}
    for name in TRACKED_LANDMARKS:
        xs = [frame[name]["x"] for frame in samples if name in frame]
        ys = [frame[name]["y"] for frame in samples if name in frame]
        averaged[name] = {
            "x": float(np.mean(xs)) if xs else 0.0,
            "y": float(np.mean(ys)) if ys else 0.0,
        }
    return averaged


def _output_path_for(video_path: str, output_dir: Path) -> Path:
    """
    Map shot.mp4 → shot_analysis.mp4 (always .mp4 for OpenCV mp4v writer).
    """
    stem = Path(video_path).stem
    # Avoid stacking suffixes if re-processing an analysis file.
    if stem.endswith("_analysis"):
        out_name = f"{stem}.mp4"
    else:
        out_name = f"{stem}_analysis.mp4"
    return output_dir / out_name


def _remux_h264(path: Path) -> Path:
    """
    Re-encode OpenCV mp4v output to H.264 so AVPlayer / video_player can play it.
    Uses the ffmpeg binary bundled with imageio-ffmpeg when system ffmpeg is absent.
    """
    try:
        import imageio_ffmpeg
    except ImportError:
        print("imageio-ffmpeg not installed; overlay may not play on iOS/macOS")
        return path

    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    tmp_path = path.with_name(f"{path.stem}_h264{path.suffix}")
    cmd = [
        ffmpeg,
        "-y",
        "-i",
        str(path),
        "-c:v",
        "libx264",
        "-preset",
        "ultrafast",
        "-crf",
        "20",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        "-an",
        str(tmp_path),
    ]
    print("H264 remux:", " ".join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0 or not tmp_path.exists() or tmp_path.stat().st_size <= 0:
        print("H264 remux failed:", result.stderr[-800:] if result.stderr else result.stdout)
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass
        return path

    tmp_path.replace(path)
    print("H264 remux ok:", path, "size=", path.stat().st_size)
    return path


def analyze_pose(video_path: str) -> dict[str, Any]:
    """
    Open a video, run MediaPipe Pose on each frame, and return detection stats
    plus averaged landmark coordinates for key shooting joints.
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Could not open video: {video_path}")

    mp_pose = mp.solutions.pose
    frames_processed = 0
    frames_with_pose = 0
    landmark_samples: list[dict[str, dict[str, float]]] = []

    print(f"Pose detection starting: {video_path}")

    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        enable_segmentation=False,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as pose:
        while True:
            ok, frame = cap.read()
            if not ok:
                break

            frames_processed += 1
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            result = pose.process(rgb)

            if result.pose_landmarks:
                frames_with_pose += 1
                landmark_samples.append(_extract_landmarks(result.pose_landmarks))

    cap.release()

    pose_detection_rate = (
        round((frames_with_pose / frames_processed) * 100, 2)
        if frames_processed > 0
        else 0.0
    )

    print(
        f"Pose detection done: frames={frames_processed} "
        f"posed={frames_with_pose} rate={pose_detection_rate}%"
    )

    return {
        "frames_processed": frames_processed,
        "frames_with_pose": frames_with_pose,
        "pose_detection_rate": pose_detection_rate,
        "landmarks": _average_landmarks(landmark_samples),
        "tracked": list(TRACKED_LANDMARKS.keys()),
    }


def extract_pose_landmarks_fast(
    video_path: str,
    sample_every: int | None = None,
) -> dict[str, Any]:
    """
    Fast path: MediaPipe pose on every Nth frame only.

    Does NOT render or encode an overlay video — use for scoring/report.
    """
    import time

    from video_pipeline import POSE_SAMPLE_EVERY

    every = max(1, sample_every or POSE_SAMPLE_EVERY)
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Could not open video: {video_path}")

    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 720)
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 1280)
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 30.0)
    if fps <= 1 or fps > 120:
        fps = 30.0

    mp_pose = mp.solutions.pose
    frames_seen = 0
    frames_with_pose = 0
    pose_inferences = 0
    landmark_samples: list[dict[str, dict[str, float]]] = []

    t0 = time.perf_counter()
    print(
        f"Fast pose starting: {video_path} "
        f"({width}x{height} @ {fps:.1f}fps, sample_every={every})"
    )

    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=0,
        enable_segmentation=False,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as pose:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            frames_seen += 1
            if (frames_seen - 1) % every != 0:
                continue

            pose_inferences += 1
            if frame.shape[1] != width or frame.shape[0] != height:
                frame = cv2.resize(frame, (width, height))
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            result = pose.process(rgb)
            if result.pose_landmarks:
                frames_with_pose += 1
                landmark_samples.append(_extract_landmarks(result.pose_landmarks))

    cap.release()
    elapsed = time.perf_counter() - t0
    pose_detection_rate = (
        round((frames_with_pose / max(pose_inferences, 1)) * 100, 2)
        if pose_inferences > 0
        else 0.0
    )
    print(
        f"Pose detection completed ({elapsed:.2f}s) "
        f"seen={frames_seen} pose_calls={pose_inferences} "
        f"posed={frames_with_pose} rate={pose_detection_rate}%"
    )

    return {
        "frames_processed": frames_seen,
        "frames_with_pose": frames_with_pose,
        "pose_inferences": pose_inferences,
        "pose_sample_every": every,
        "pose_detection_rate": pose_detection_rate,
        "landmarks": _average_landmarks(landmark_samples),
        "all_landmarks": landmark_samples,
        "tracked": list(TRACKED_LANDMARKS.keys()),
        "width": width,
        "height": height,
        "fps": fps,
        "pose_elapsed_s": round(elapsed, 3),
    }


def create_pose_overlay(
    video_path: str,
    output_dir: str | Path | None = None,
    source_name: str | None = None,
    sample_every: int | None = None,
    on_progress: Any | None = None,
) -> dict[str, Any]:
    """
    Draw color-coded MediaPipe Pose skeleton and export an overlay MP4.

    Speeds up analysis by running pose detection every Nth frame (default 3)
    and reusing the last skeleton on in-between frames for smooth video.
    """
    from shooting_analysis import evaluate_frame_joint_status
    from video_pipeline import POSE_SAMPLE_EVERY

    output_dir = Path(output_dir) if output_dir else PROCESSED_VIDEOS_DIR
    output_dir.mkdir(parents=True, exist_ok=True)
    every = max(1, sample_every or POSE_SAMPLE_EVERY)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Could not open video: {video_path}")

    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 1080)
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 1920)
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 30.0)
    if fps <= 1 or fps > 120:
        fps = 30.0

    naming_source = source_name or video_path
    out_path = _output_path_for(naming_source, output_dir)
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(out_path), fourcc, fps, (width, height))
    if not writer.isOpened():
        cap.release()
        raise RuntimeError(f"Could not open video writer: {out_path}")

    if on_progress:
        on_progress("detecting_pose", 40)

    mp_pose = mp.solutions.pose
    frames_processed = 0
    frames_with_pose = 0
    pose_inferences = 0
    landmark_samples: list[dict[str, dict[str, float]]] = []
    last_sample: dict[str, dict[str, float]] | None = None
    last_status: dict[str, str] | None = None

    print(
        f"Skeleton overlay starting: {video_path} → {out_path} "
        f"({width}x{height} @ {fps:.2f}fps, sample_every={every})"
    )

    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=0,  # faster than complexity=1 for mobile uploads
        enable_segmentation=False,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as pose:
        while True:
            ok, frame = cap.read()
            if not ok:
                break

            if frame.shape[1] != width or frame.shape[0] != height:
                frame = cv2.resize(frame, (width, height))

            frames_processed += 1
            run_pose = (frames_processed - 1) % every == 0 or last_sample is None

            if run_pose:
                pose_inferences += 1
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                result = pose.process(rgb)
                if result.pose_landmarks:
                    frames_with_pose += 1
                    last_sample = _extract_landmarks(result.pose_landmarks)
                    last_status = evaluate_frame_joint_status(last_sample)
                    landmark_samples.append(last_sample)
                    _draw_colored_skeleton(
                        frame,
                        result.pose_landmarks,
                        last_status,
                    )
            elif last_sample is not None and last_status is not None:
                # Carry forward skeleton so playback stays smooth.
                _draw_colored_skeleton_from_sample(frame, last_sample, last_status)

            writer.write(frame)

            if on_progress and frames_processed % 30 == 0:
                on_progress("detecting_pose", 40)

    cap.release()
    writer.release()

    if on_progress:
        on_progress("analyzing_mechanics", 70)

    pose_detection_rate = (
        round((frames_with_pose / max(pose_inferences, 1)) * 100, 2)
        if pose_inferences > 0
        else 0.0
    )

    if not out_path.exists() or out_path.stat().st_size <= 0:
        raise RuntimeError(f"Overlay video was not written: {out_path}")

    out_path = _remux_h264(out_path)

    print(
        f"Skeleton overlay done: frames={frames_processed} "
        f"pose_calls={pose_inferences} posed={frames_with_pose} "
        f"rate={pose_detection_rate}% size={out_path.stat().st_size} "
        f"path={out_path}"
    )

    return {
        "analysis_video": str(out_path),
        "analysis_video_name": out_path.name,
        "frames_processed": frames_processed,
        "frames_with_pose": frames_with_pose,
        "pose_inferences": pose_inferences,
        "pose_sample_every": every,
        "pose_detection_rate": pose_detection_rate,
        "landmarks": _average_landmarks(landmark_samples),
        "all_landmarks": landmark_samples,
        "tracked": list(TRACKED_LANDMARKS.keys()),
        "width": width,
        "height": height,
        "fps": fps,
    }
