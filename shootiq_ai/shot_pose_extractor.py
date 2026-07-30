"""
Basketball Shot Pose Extractor
--------------------------------
Reads a video file, runs MediaPipe Pose on every frame, computes joint
angles (knee, hip, elbow, wrist) for both sides of the body using 3D
(x, y, z) vectors, and writes a frame-by-frame JSON file.

Also used by pose_pipeline.py / FastAPI /analyze.

SETUP (run once):
    pip install mediapipe opencv-python numpy

USAGE:
    python shot_pose_extractor.py path/to/video.mp4
    python shot_pose_extractor.py path/to/video.mp4 --output my_shot.json
    python shot_pose_extractor.py path/to/video.mp4 --side right
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

import cv2
import mediapipe as mp
import numpy as np

mp_pose = mp.solutions.pose

# MediaPipe pose landmark indices we care about
LANDMARK_NAMES = {
    "nose": 0,
    "left_shoulder": 11, "right_shoulder": 12,
    "left_elbow": 13, "right_elbow": 14,
    "left_wrist": 15, "right_wrist": 16,
    "left_pinky": 17, "right_pinky": 18,
    "left_index": 19, "right_index": 20,
    "left_hip": 23, "right_hip": 24,
    "left_knee": 25, "right_knee": 26,
    "left_ankle": 27, "right_ankle": 28,
    "left_foot_index": 31, "right_foot_index": 32,
}

_SIDES = ("left", "right")


def angle_between(a, b, c):
    """
    Angle at point b, formed by rays b->a and b->c, in degrees.
    a, b, c are (x, y) or (x, y, z) tuples.
    """
    a, b, c = np.array(a), np.array(b), np.array(c)
    ba = a - b
    bc = c - b
    cos_angle = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-9)
    cos_angle = np.clip(cos_angle, -1.0, 1.0)
    return math.degrees(math.acos(cos_angle))


def _filter_sides(side: str | None) -> tuple[str, ...]:
    if side is None or side == "both":
        return _SIDES
    side_l = side.lower().strip()
    if side_l not in _SIDES:
        raise ValueError(f"side must be left, right, or both (got {side!r})")
    return (side_l,)


def _point_from_mapping(
    landmarks: Mapping[str, Mapping[str, Any]],
    name: str,
    use_z: bool = True,
) -> tuple[float, ...] | None:
    lm = landmarks.get(name)
    if not lm:
        return None
    try:
        x, y = float(lm["x"]), float(lm["y"])
    except (KeyError, TypeError, ValueError):
        return None
    if use_z:
        try:
            return (x, y, float(lm.get("z", 0.0)))
        except (TypeError, ValueError):
            return (x, y, 0.0)
    return (x, y)


def get_point(landmarks, name, use_z=True):
    """Read a named joint from a MediaPipe landmark list (3D by default)."""
    idx = LANDMARK_NAMES[name]
    lm = landmarks[idx]
    if use_z:
        return (lm.x, lm.y, lm.z)
    return (lm.x, lm.y)


def compute_angles(landmarks, use_z=True, side=None):
    """Compute joint angles using 3D (x, y, z) vectors by default."""
    angles = {}

    for body_side in _filter_sides(side):
        try:
            shoulder = get_point(landmarks, f"{body_side}_shoulder", use_z)
            elbow = get_point(landmarks, f"{body_side}_elbow", use_z)
            wrist = get_point(landmarks, f"{body_side}_wrist", use_z)
            index = get_point(landmarks, f"{body_side}_index", use_z)
            hip = get_point(landmarks, f"{body_side}_hip", use_z)
            knee = get_point(landmarks, f"{body_side}_knee", use_z)
            ankle = get_point(landmarks, f"{body_side}_ankle", use_z)

            angles[f"{body_side}_elbow"] = round(angle_between(shoulder, elbow, wrist), 1)
            angles[f"{body_side}_wrist"] = round(angle_between(elbow, wrist, index), 1)
            angles[f"{body_side}_shoulder"] = round(angle_between(hip, shoulder, elbow), 1)
            angles[f"{body_side}_hip"] = round(angle_between(shoulder, hip, knee), 1)
            angles[f"{body_side}_knee"] = round(angle_between(hip, knee, ankle), 1)
        except (KeyError, IndexError, AttributeError):
            continue

    return angles


def compute_angles_from_landmarks(
    landmarks: Mapping[str, Mapping[str, Any]],
    use_z: bool = True,
    side: str | None = None,
) -> dict[str, float]:
    """Compute joint angles from landmark dicts (3D by default)."""
    angles: dict[str, float] = {}

    for body_side in _filter_sides(side):
        shoulder = _point_from_mapping(landmarks, f"{body_side}_shoulder", use_z)
        elbow = _point_from_mapping(landmarks, f"{body_side}_elbow", use_z)
        wrist = _point_from_mapping(landmarks, f"{body_side}_wrist", use_z)
        index = _point_from_mapping(landmarks, f"{body_side}_index", use_z)
        hip = _point_from_mapping(landmarks, f"{body_side}_hip", use_z)
        knee = _point_from_mapping(landmarks, f"{body_side}_knee", use_z)
        ankle = _point_from_mapping(landmarks, f"{body_side}_ankle", use_z)

        if None in (shoulder, elbow, wrist, hip, knee, ankle):
            continue

        angles[f"{body_side}_elbow"] = round(
            angle_between(shoulder, elbow, wrist), 1  # type: ignore[arg-type]
        )
        if index is not None:
            angles[f"{body_side}_wrist"] = round(
                angle_between(elbow, wrist, index), 1  # type: ignore[arg-type]
            )
        angles[f"{body_side}_shoulder"] = round(
            angle_between(hip, shoulder, elbow), 1  # type: ignore[arg-type]
        )
        angles[f"{body_side}_hip"] = round(
            angle_between(shoulder, hip, knee), 1  # type: ignore[arg-type]
        )
        angles[f"{body_side}_knee"] = round(
            angle_between(hip, knee, ankle), 1  # type: ignore[arg-type]
        )

    return angles


def extract_named_landmarks(
    pose_landmarks: Any,
    names: Iterable[str] | None = None,
) -> dict[str, dict[str, float]]:
    """Pull named x/y/z/visibility from a MediaPipe pose result."""
    wanted = list(names) if names is not None else list(LANDMARK_NAMES.keys())
    points: dict[str, dict[str, float]] = {}
    for name in wanted:
        idx = LANDMARK_NAMES.get(name)
        if idx is None:
            continue
        lm = pose_landmarks.landmark[idx]
        points[name] = {
            "x": round(float(lm.x), 4),
            "y": round(float(lm.y), 4),
            "z": round(float(lm.z), 4),
            "visibility": round(float(lm.visibility), 3),
        }
    return points


def annotate_pose_frames(
    pose_frames: Sequence[Mapping[str, Any]],
    side: str | None = None,
) -> list[dict[str, Any]]:
    """Add/refresh an `angles` dict on each pose_pipeline frame entry."""
    out: list[dict[str, Any]] = []
    for frame in pose_frames:
        entry = dict(frame)
        landmarks = entry.get("landmarks")
        if isinstance(landmarks, dict) and landmarks:
            entry["angles"] = compute_angles_from_landmarks(landmarks, side=side)
        else:
            entry["angles"] = {}
        out.append(entry)
    return out


def build_shot_angles_payload(
    *,
    video_path: str | Path,
    fps: float,
    frames: Sequence[Mapping[str, Any]],
    total_frames: int | None = None,
) -> dict[str, Any]:
    """CLI-compatible shot_angles.json payload from annotated pose frames."""
    results_out: list[dict[str, Any]] = []
    for frame in frames:
        frame_number = int(frame.get("frame_number", frame.get("frame", 0)))
        time_sec = frame.get("time_sec", frame.get("timestamp"))
        if time_sec is None:
            time_sec = round(frame_number / (fps or 30.0), 3)
        landmarks = frame.get("landmarks") or {}
        angles = frame.get("angles")
        if not isinstance(angles, dict):
            angles = (
                compute_angles_from_landmarks(landmarks)
                if isinstance(landmarks, dict)
                else {}
            )
        results_out.append(
            {
                "frame": frame_number,
                "time_sec": round(float(time_sec), 3),
                "pose_detected": bool(landmarks),
                "angles": angles,
                "landmarks": landmarks if isinstance(landmarks, dict) else {},
            }
        )

    return {
        "video_path": str(video_path),
        "fps": float(fps),
        "total_frames": int(total_frames if total_frames is not None else len(results_out)),
        "frames": results_out,
    }


def process_video(
    video_path,
    output_path,
    side=None,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5,
):
    """Extract pose angles/landmarks. Returns the JSON payload (also writes file)."""
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Could not open video at {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frame_count = 0
    results_out = []

    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=2,
        min_detection_confidence=min_detection_confidence,
        min_tracking_confidence=min_tracking_confidence,
    ) as pose:
        while cap.isOpened():
            success, frame = cap.read()
            if not success:
                break

            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            result = pose.process(rgb_frame)

            frame_entry = {
                "frame": frame_count,
                "time_sec": round(frame_count / fps, 3),
                "pose_detected": result.pose_landmarks is not None,
                "angles": {},
                "landmarks": {},
            }

            if result.pose_landmarks:
                landmarks = result.pose_landmarks.landmark
                # Always use 3D coordinates for angles.
                frame_entry["angles"] = compute_angles(
                    landmarks, use_z=True, side=side
                )
                for name, idx in LANDMARK_NAMES.items():
                    lm = landmarks[idx]
                    frame_entry["landmarks"][name] = {
                        "x": round(lm.x, 4),
                        "y": round(lm.y, 4),
                        "z": round(lm.z, 4),
                        "visibility": round(lm.visibility, 3),
                    }

            results_out.append(frame_entry)
            frame_count += 1

            if frame_count % 30 == 0:
                print(f"Processed {frame_count} frames...")

    cap.release()

    output = {
        "video_path": str(video_path),
        "fps": fps,
        "total_frames": frame_count,
        "frames": results_out,
    }

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)

    print(f"\nDone. {frame_count} frames processed.")
    print(f"Output written to: {output_path}")

    valid_frames = [f for f in results_out if f["angles"]]
    if valid_frames:
        knee_key = (
            "right_knee"
            if any("right_knee" in f["angles"] for f in valid_frames)
            else "left_knee"
        )
        wrist_key = (
            "right_wrist"
            if any("right_wrist" in f["angles"] for f in valid_frames)
            else "left_wrist"
        )
        knee_frames = [f for f in valid_frames if knee_key in f["angles"]]
        wrist_frames = [f for f in valid_frames if wrist_key in f["angles"]]
        if knee_frames:
            deepest = min(knee_frames, key=lambda f: f["angles"][knee_key])
            print(
                f"\nDeepest knee bend: frame {deepest['frame']} "
                f"({deepest['time_sec']}s) at {deepest['angles'][knee_key]}°"
            )
        if wrist_frames:
            snap = max(wrist_frames, key=lambda f: f["angles"][wrist_key])
            print(
                f"Fullest wrist extension: frame {snap['frame']} "
                f"({snap['time_sec']}s) at {snap['angles'][wrist_key]}°"
            )

    return output


def main():
    parser = argparse.ArgumentParser(
        description="Extract pose angles from a basketball shot video."
    )
    parser.add_argument("video", help="Path to the input video file")
    parser.add_argument(
        "--output", default="shot_angles.json", help="Path to output JSON file"
    )
    parser.add_argument(
        "--side",
        choices=("left", "right", "both"),
        default="both",
        help="Which body side to extract angles for (default: both)",
    )
    args = parser.parse_args()

    side = None if args.side == "both" else args.side
    try:
        process_video(args.video, args.output, side=side)
    except RuntimeError as exc:
        print(f"Error: {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
