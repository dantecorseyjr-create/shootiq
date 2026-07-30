"""
ShootIQ Step 4 — MediaPipe Pose Detection foundation.

Responsibilities (no biomechanics scoring):
1. Open video with OpenCV
2. Sample frames at a configurable rate
3. Run MediaPipe Pose
4. Save pose_data.json + basic skeleton_overlay.mp4
5. Keep a copy of the source as original_video.mp4
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

import cv2
import mediapipe as mp
import numpy as np

from follow_through_analyzer import run_follow_through_analysis
from shot_pose_extractor import (
    build_shot_angles_payload,
    compute_angles_from_landmarks,
)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Analyze every Nth frame (1 = every frame). Scoring uses 1 for stability.
POSE_SAMPLE_EVERY = 1

BASE_DIR = Path(__file__).resolve().parent
PROCESSED_VIDEOS_DIR = BASE_DIR / "processed_videos"
POSE_RUNS_DIR = PROCESSED_VIDEOS_DIR / "pose_runs"

# MediaPipe Pose landmark indices we track for basketball form.
NOSE = 0
LEFT_SHOULDER = 11
RIGHT_SHOULDER = 12
LEFT_ELBOW = 13
RIGHT_ELBOW = 14
LEFT_WRIST = 15
RIGHT_WRIST = 16
LEFT_PINKY = 17
RIGHT_PINKY = 18
LEFT_INDEX = 19
RIGHT_INDEX = 20
LEFT_HIP = 23
RIGHT_HIP = 24
LEFT_KNEE = 25
RIGHT_KNEE = 26
LEFT_ANKLE = 27
RIGHT_ANKLE = 28
LEFT_FOOT_INDEX = 31
RIGHT_FOOT_INDEX = 32

TRACKED_LANDMARKS: dict[str, int] = {
    "nose": NOSE,
    "left_shoulder": LEFT_SHOULDER,
    "right_shoulder": RIGHT_SHOULDER,
    "left_elbow": LEFT_ELBOW,
    "right_elbow": RIGHT_ELBOW,
    "left_wrist": LEFT_WRIST,
    "right_wrist": RIGHT_WRIST,
    "left_pinky": LEFT_PINKY,
    "right_pinky": RIGHT_PINKY,
    "left_index": LEFT_INDEX,
    "right_index": RIGHT_INDEX,
    "left_hip": LEFT_HIP,
    "right_hip": RIGHT_HIP,
    "left_knee": LEFT_KNEE,
    "right_knee": RIGHT_KNEE,
    "left_ankle": LEFT_ANKLE,
    "right_ankle": RIGHT_ANKLE,
    "left_foot_index": LEFT_FOOT_INDEX,
    "right_foot_index": RIGHT_FOOT_INDEX,
}

# Basic stick-figure bones (no scoring colors).
_SKELETON_BONES: list[tuple[str, str]] = [
    ("nose", "left_shoulder"),
    ("nose", "right_shoulder"),
    ("left_shoulder", "right_shoulder"),
    ("left_shoulder", "left_elbow"),
    ("left_elbow", "left_wrist"),
    ("right_shoulder", "right_elbow"),
    ("right_elbow", "right_wrist"),
    ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"),
    ("left_hip", "right_hip"),
    ("left_hip", "left_knee"),
    ("left_knee", "left_ankle"),
    ("right_hip", "right_knee"),
    ("right_knee", "right_ankle"),
]

_JOINT_COLOR = (255, 200, 80)   # BGR default (unused when scored)
_BONE_COLOR = (255, 255, 255)   # white default
_VISIBILITY_MIN = 0.35

# Step 5 overlay colors (BGR).
_STATUS_BGR = {
    "PASS": (60, 200, 80),        # GREEN
    "WARN": (40, 200, 240),       # YELLOW
    "NEEDS_WORK": (40, 200, 240), # alias
    "FAIL": (50, 50, 230),        # RED
}

# Bone / joint → status key for highlighting failing segments.
_BONE_STATUS_KEY: dict[tuple[str, str], str] = {
    ("nose", "left_shoulder"): "torso",
    ("nose", "right_shoulder"): "torso",
    ("left_shoulder", "right_shoulder"): "torso",
    ("left_shoulder", "left_elbow"): "elbow",
    ("left_elbow", "left_wrist"): "elbow",
    ("right_shoulder", "right_elbow"): "elbow",
    ("right_elbow", "right_wrist"): "elbow",
    ("left_shoulder", "left_hip"): "torso",
    ("right_shoulder", "right_hip"): "torso",
    ("left_hip", "right_hip"): "torso",
    ("left_hip", "left_knee"): "knee",
    ("left_knee", "left_ankle"): "knee",
    ("right_hip", "right_knee"): "knee",
    ("right_knee", "right_ankle"): "knee",
}

_JOINT_STATUS_KEY: dict[str, str] = {
    "nose": "torso",
    "left_shoulder": "shoulder",
    "right_shoulder": "shoulder",
    "left_elbow": "elbow",
    "right_elbow": "elbow",
    "left_wrist": "wrist",
    "right_wrist": "wrist",
    "left_hip": "hip",
    "right_hip": "hip",
    "left_knee": "knee",
    "right_knee": "knee",
    "left_ankle": "ankle",
    "right_ankle": "ankle",
}


# ---------------------------------------------------------------------------
# Landmark helpers
# ---------------------------------------------------------------------------

def extract_landmarks(pose_landmarks: Any) -> dict[str, dict[str, float]]:
    """Pull tracked x/y/z/visibility from a MediaPipe pose result."""
    points: dict[str, dict[str, float]] = {}
    for name, index in TRACKED_LANDMARKS.items():
        lm = pose_landmarks.landmark[index]
        points[name] = {
            "x": float(lm.x),
            "y": float(lm.y),
            "z": float(lm.z),
            "visibility": float(lm.visibility),
        }
    return points


def landmarks_for_scoring(
    pose_frames: list[dict[str, Any]],
) -> list[dict[str, dict[str, float]]]:
    """Flatten Step-4 pose frames into the list shape biomechanics expects."""
    return [
        frame["landmarks"]
        for frame in pose_frames
        if isinstance(frame.get("landmarks"), dict) and frame["landmarks"]
    ]


def average_landmarks(
    samples: list[dict[str, dict[str, float]]],
) -> dict[str, dict[str, float]]:
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


# ---------------------------------------------------------------------------
# Drawing — basic skeleton (no red/green scoring)
# ---------------------------------------------------------------------------

def draw_basic_skeleton(
    frame: np.ndarray,
    landmarks: dict[str, dict[str, float]],
    status: dict[str, str] | None = None,
) -> None:
    """
    Draw joints as circles and bones as lines on a BGR frame.

    When [status] is provided (PASS/WARN/FAIL), failing segments turn red/yellow.
    """
    h, w = frame.shape[:2]

    def pt(name: str) -> tuple[int, int] | None:
        data = landmarks.get(name)
        if not data:
            return None
        if float(data.get("visibility", 0.0)) < _VISIBILITY_MIN:
            return None
        return int(data["x"] * w), int(data["y"] * h)

    def color_for(key: str) -> tuple[int, int, int]:
        if not status:
            return _BONE_COLOR
        return _STATUS_BGR.get(status.get(key, "PASS"), _BONE_COLOR)

    for a, b in _SKELETON_BONES:
        pa, pb = pt(a), pt(b)
        if pa is None or pb is None:
            continue
        key = _BONE_STATUS_KEY.get((a, b), "torso")
        cv2.line(frame, pa, pb, color_for(key), 3, lineType=cv2.LINE_AA)

    # Draw core stick-figure joints only (hand/foot tip landmarks are for angles).
    for name in _JOINT_STATUS_KEY:
        p = pt(name)
        if p is None:
            continue
        key = _JOINT_STATUS_KEY.get(name, "torso")
        joint_color = color_for(key) if status else _JOINT_COLOR
        cv2.circle(frame, p, 6, joint_color, -1, lineType=cv2.LINE_AA)
        cv2.circle(frame, p, 7, (255, 255, 255), 1, lineType=cv2.LINE_AA)


# ---------------------------------------------------------------------------
# H.264 remux for player compatibility
# ---------------------------------------------------------------------------

def _remux_h264(path: Path) -> Path:
    try:
        import imageio_ffmpeg
    except ImportError:
        print("imageio-ffmpeg not installed; overlay may not play on iOS/macOS")
        return path

    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    tmp_path = path.with_name(f"{path.stem}_h264{path.suffix}")
    cmd = [
        ffmpeg, "-y", "-i", str(path),
        "-c:v", "libx264", "-preset", "ultrafast", "-crf", "20",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an",
        str(tmp_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0 or not tmp_path.exists() or tmp_path.stat().st_size <= 0:
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass
        return path
    tmp_path.replace(path)
    return path


# ---------------------------------------------------------------------------
# Main Step 4 pipeline
# ---------------------------------------------------------------------------

def run_pose_detection(
    video_path: str | Path,
    output_dir: str | Path | None = None,
    sample_every: int | None = None,
    write_overlay: bool = True,
) -> dict[str, Any]:
    """
    Run MediaPipe Pose on a video and persist Step-4 artifacts.

    Writes into output_dir:
      - original_video.mp4
      - pose_data.json          (landmarks + per-frame joint angles)
      - shot_angles.json        (CLI-compatible angle timeline)
      - follow_through_analysis.json  (elbow flare + hold analysis)
      - skeleton_overlay.mp4  (if write_overlay=True)
    """
    src = Path(video_path)
    if not src.exists():
        raise FileNotFoundError(f"Video not found: {src}")

    every = max(1, sample_every if sample_every is not None else POSE_SAMPLE_EVERY)
    out_dir = Path(output_dir) if output_dir else (POSE_RUNS_DIR / src.stem)
    out_dir.mkdir(parents=True, exist_ok=True)

    # --- Keep original ---
    original_out = out_dir / "original_video.mp4"
    if src.resolve() != original_out.resolve():
        shutil.copy2(src, original_out)

    # --- Open video ---
    cap = cv2.VideoCapture(str(src))
    if not cap.isOpened():
        raise ValueError(f"Could not open video: {src}")
    print("Video loaded")

    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH) or 720)
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT) or 1280)
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 30.0)
    if fps <= 1 or fps > 120:
        fps = 30.0
    total_hint = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)

    overlay_raw = out_dir / "skeleton_overlay_raw.mp4"
    overlay_out = out_dir / "skeleton_overlay.mp4"

    print("MediaPipe initialized")
    mp_pose = mp.solutions.pose

    frames_seen = 0
    frames_extracted = 0
    frames_with_pose = 0
    pose_frames: list[dict[str, Any]] = []
    last_landmarks: dict[str, dict[str, float]] | None = None
    # Hold-forward landmarks for every video frame (used by phase-aware overlay).
    landmarks_by_video_frame: dict[int, dict[str, dict[str, float]]] = {}

    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=2,  # more stable landmarks (repeatability)
        enable_segmentation=False,
        min_detection_confidence=0.55,
        min_tracking_confidence=0.55,
        smooth_landmarks=True,
    ) as pose:
        while True:
            ok, frame = cap.read()
            if not ok:
                break

            frames_seen += 1
            if frame.shape[1] != width or frame.shape[0] != height:
                frame = cv2.resize(frame, (width, height))

            run_pose = (frames_seen - 1) % every == 0 or last_landmarks is None
            if run_pose:
                frames_extracted += 1
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                result = pose.process(rgb)
                held_forward = False
                if result.pose_landmarks:
                    frames_with_pose += 1
                    last_landmarks = extract_landmarks(result.pose_landmarks)
                elif last_landmarks is not None:
                    # Keep timeline length stable — never drop a sample slot.
                    held_forward = True
                if last_landmarks is not None:
                    pose_frames.append(
                        {
                            "frame_number": frames_seen - 1,
                            "timestamp": round((frames_seen - 1) / fps, 4),
                            "landmarks": last_landmarks,
                            "angles": compute_angles_from_landmarks(
                                last_landmarks
                            ),
                            "held_forward": held_forward,
                        }
                    )

            if last_landmarks is not None:
                landmarks_by_video_frame[frames_seen - 1] = last_landmarks

    cap.release()

    print("Frames extracted")
    print(f"Pose detected on {frames_with_pose} frames")

    # AI shot-phase detection (temporal motion classifier) for overlay + pose_data.
    phases: dict[str, Any] = {}
    try:
        from pose_utils import (
            as_frames,
            resolve_clip_shooting_side,
            set_clip_shooting_side,
        )
        from shot_phases import detect_shot_phases, phase_name_for_index

        side_frames = as_frames(pose_frames)
        set_clip_shooting_side(resolve_clip_shooting_side(side_frames))
        try:
            phases = detect_shot_phases(
                {"frames": pose_frames, "sample_every": every, "fps": fps},
                fps=fps,
                sample_every=every,
            )
        finally:
            set_clip_shooting_side(None)
    except Exception as exc:  # noqa: BLE001
        print("Phase detection skipped:", exc)
        phase_name_for_index = None  # type: ignore[assignment]

    # Map video frame → nearest sampled pose index for phase lookup.
    sample_index_by_video: dict[int, int] = {}
    for idx, item in enumerate(pose_frames):
        sample_index_by_video[int(item["frame_number"])] = idx
    sorted_sample_frames = sorted(sample_index_by_video.keys())

    def _sample_index_for_video(video_frame: int) -> int:
        if not sorted_sample_frames:
            return 0
        # Nearest sampled frame at or before this video frame.
        best = sorted_sample_frames[0]
        for sf in sorted_sample_frames:
            if sf <= video_frame:
                best = sf
            else:
                break
        return sample_index_by_video[best]

    # --- Save pose_data.json ---
    pose_payload = {
        "video": str(src.name),
        "width": width,
        "height": height,
        "fps": fps,
        "sample_every": every,
        "frames_total": frames_seen,
        "frames_sampled": frames_extracted,
        "frames_with_pose": frames_with_pose,
        "tracked_landmarks": list(TRACKED_LANDMARKS.keys()),
        "phases": {
            key: phases[key]
            for key in (
                "setup",
                "gather",
                "knee_load",
                "set_point",
                "release",
                "follow_through",
                "landing",
            )
            if key in phases
        },
        "frame_phases": phases.get("frame_phases", []),
        "phase_detector": phases.get("detector", {}),
        "frames": pose_frames,
    }
    pose_json_path = out_dir / "pose_data.json"
    pose_json_path.write_text(json.dumps(pose_payload, indent=2), encoding="utf-8")
    print("Landmarks saved")

    # --- Save shot_angles.json (same schema as shot_pose_extractor CLI) ---
    shot_angles_payload = build_shot_angles_payload(
        video_path=src,
        fps=fps,
        frames=pose_frames,
        total_frames=frames_seen,
    )
    shot_angles_path = out_dir / "shot_angles.json"
    shot_angles_path.write_text(
        json.dumps(shot_angles_payload, indent=2),
        encoding="utf-8",
    )
    print("Shot angles saved")

    # --- Elbow alignment + follow-through hold (from shot_angles) ---
    follow_through_analysis: dict[str, Any] = {}
    follow_through_path = out_dir / "follow_through_analysis.json"
    try:
        follow_through_analysis = run_follow_through_analysis(
            shot_angles_payload,
            source_file=str(shot_angles_path),
        )
        follow_through_path.write_text(
            json.dumps(follow_through_analysis, indent=2),
            encoding="utf-8",
        )
        print("Follow-through / elbow alignment analysis saved")
    except Exception as exc:  # noqa: BLE001
        print("Follow-through analysis skipped:", exc)
        follow_through_analysis = {}

    # --- Phase-aware skeleton overlay (second pass) ---
    skeleton_path: Path | None = None
    if write_overlay and frames_seen > 0:
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        writer = cv2.VideoWriter(str(overlay_raw), fourcc, fps, (width, height))
        if not writer.isOpened():
            raise RuntimeError(f"Could not open video writer: {overlay_raw}")

        cap2 = cv2.VideoCapture(str(src))
        video_i = 0
        while True:
            ok, frame = cap2.read()
            if not ok:
                break
            if frame.shape[1] != width or frame.shape[0] != height:
                frame = cv2.resize(frame, (width, height))
            draw_frame = frame.copy()
            lm = landmarks_by_video_frame.get(video_i)
            if lm is not None:
                joint_status = None
                try:
                    from biomechanics_engine import evaluate_frame_joint_status

                    phase_key = None
                    if phases and phase_name_for_index is not None:
                        phase_key = phase_name_for_index(
                            phases, _sample_index_for_video(video_i)
                        )
                    joint_status = evaluate_frame_joint_status(lm, phase=phase_key)
                except Exception:  # noqa: BLE001
                    joint_status = None
                draw_basic_skeleton(draw_frame, lm, joint_status)
            writer.write(draw_frame)
            video_i += 1
        cap2.release()
        writer.release()

        skeleton_path = _remux_h264(overlay_raw)
        if skeleton_path.resolve() != overlay_out.resolve():
            shutil.move(str(skeleton_path), str(overlay_out))
            skeleton_path = overlay_out
        if overlay_raw.exists() and overlay_raw.resolve() != overlay_out.resolve():
            try:
                overlay_raw.unlink()
            except OSError:
                pass
        if not overlay_out.exists() and skeleton_path and skeleton_path.exists():
            shutil.copy2(skeleton_path, overlay_out)
        skeleton_path = overlay_out if overlay_out.exists() else skeleton_path

    detection_rate = round(
        (frames_with_pose / max(frames_extracted, 1)) * 100,
        2,
    )

    print(
        f"Step4 pose complete: total={frames_seen} "
        f"(hint={total_hint}) sampled={frames_extracted} "
        f"posed={frames_with_pose} rate={detection_rate}% "
        f"out={out_dir}"
    )

    return {
        "output_dir": str(out_dir),
        "original_video": str(original_out),
        "pose_data_json": str(pose_json_path),
        "shot_angles_json": str(shot_angles_path),
        "follow_through_analysis_json": str(follow_through_path),
        "follow_through_analysis": follow_through_analysis,
        "skeleton_overlay": str(skeleton_path) if skeleton_path else None,
        "frames_processed": frames_seen,
        "frames_sampled": frames_extracted,
        "frames_with_pose": frames_with_pose,
        "pose_sample_every": every,
        "pose_detection_rate": detection_rate,
        "fps": fps,
        "width": width,
        "height": height,
        "pose_frames": pose_frames,
        "all_landmarks": landmarks_for_scoring(pose_frames),
        "landmarks": average_landmarks(landmarks_for_scoring(pose_frames)),
        "tracked": list(TRACKED_LANDMARKS.keys()),
        "mediapipe_ok": frames_with_pose > 0,
    }


def run_pose_detection_cli(video_path: str, sample_every: int = POSE_SAMPLE_EVERY) -> dict[str, Any]:
    """Convenience entry for scripts / manual testing."""
    return run_pose_detection(
        video_path=video_path,
        sample_every=sample_every,
        write_overlay=True,
    )


def render_overlay_from_saved_pose(
    video_path: str | Path,
    output_dir: str | Path,
) -> Path | None:
    """
    Draw skeleton_overlay.mp4 from an existing pose_data.json — no MediaPipe re-run.

    Keeps overlay landmarks identical to the scored analysis pass.
    """
    src = Path(video_path)
    out_dir = Path(output_dir)
    pose_json_path = out_dir / "pose_data.json"
    if not src.exists() or not pose_json_path.exists():
        return None

    payload = json.loads(pose_json_path.read_text(encoding="utf-8"))
    pose_frames = payload.get("frames") or []
    phases = {
        **(payload.get("phases") or {}),
        "frame_phases": payload.get("frame_phases") or [],
        "detector": payload.get("phase_detector") or {},
        "fps": payload.get("fps"),
    }
    fps = float(payload.get("fps") or 30.0)
    width = int(payload.get("width") or 720)
    height = int(payload.get("height") or 1280)

    # Hold-forward landmarks onto every video frame index.
    landmarks_by_video_frame: dict[int, dict[str, dict[str, float]]] = {}
    sample_index_by_video: dict[int, int] = {}
    last: dict[str, dict[str, float]] | None = None
    for idx, item in enumerate(pose_frames):
        fn = int(item.get("frame_number", idx))
        lm = item.get("landmarks")
        if isinstance(lm, dict) and lm:
            last = lm
            sample_index_by_video[fn] = idx
            landmarks_by_video_frame[fn] = lm

    if last is None:
        return None

    sorted_sample_frames = sorted(sample_index_by_video.keys())

    def _sample_index_for_video(video_frame: int) -> int:
        if not sorted_sample_frames:
            return 0
        best = sorted_sample_frames[0]
        for sf in sorted_sample_frames:
            if sf <= video_frame:
                best = sf
            else:
                break
        return sample_index_by_video[best]

    # Fill gaps between sampled frames for continuous overlay.
    cap = cv2.VideoCapture(str(src))
    if not cap.isOpened():
        return None
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    filled_last = last
    for i in range(max(total, max(landmarks_by_video_frame.keys(), default=0) + 1)):
        if i in landmarks_by_video_frame:
            filled_last = landmarks_by_video_frame[i]
        else:
            landmarks_by_video_frame[i] = filled_last

    overlay_raw = out_dir / "skeleton_overlay_raw.mp4"
    overlay_out = out_dir / "skeleton_overlay.mp4"
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(str(overlay_raw), fourcc, fps, (width, height))
    if not writer.isOpened():
        cap.release()
        return None

    try:
        from biomechanics_engine import evaluate_frame_joint_status
        from shot_phases import phase_name_for_index
    except Exception:  # noqa: BLE001
        evaluate_frame_joint_status = None  # type: ignore[assignment]
        phase_name_for_index = None  # type: ignore[assignment]

    video_i = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame.shape[1] != width or frame.shape[0] != height:
            frame = cv2.resize(frame, (width, height))
        draw_frame = frame.copy()
        lm = landmarks_by_video_frame.get(video_i)
        if lm is not None:
            joint_status = None
            if evaluate_frame_joint_status is not None:
                try:
                    phase_key = None
                    if phases and phase_name_for_index is not None:
                        phase_key = phase_name_for_index(
                            phases, _sample_index_for_video(video_i)
                        )
                    joint_status = evaluate_frame_joint_status(lm, phase=phase_key)
                except Exception:  # noqa: BLE001
                    joint_status = None
            draw_basic_skeleton(draw_frame, lm, joint_status)
        writer.write(draw_frame)
        video_i += 1
    cap.release()
    writer.release()

    skeleton_path = _remux_h264(overlay_raw)
    if skeleton_path.resolve() != overlay_out.resolve():
        shutil.move(str(skeleton_path), str(overlay_out))
        skeleton_path = overlay_out
    if overlay_raw.exists() and overlay_raw.resolve() != overlay_out.resolve():
        try:
            overlay_raw.unlink()
        except OSError:
            pass
    return overlay_out if overlay_out.exists() else skeleton_path
