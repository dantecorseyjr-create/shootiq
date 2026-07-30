"""Shared MediaPipe landmark helpers for ShootIQ AI."""

from __future__ import annotations

import math
from typing import Any, Sequence

Point = tuple[float, float]
Point3 = tuple[float, float, float]
FrameLandmarks = dict[str, dict[str, float]]

# Clip-level shooting side — set once per analysis so left/right never flips
# mid-shot from MediaPipe wrist jitter (major source of score inconsistency).
_clip_shooting_side: str | None = None


def calculate_angle(point1: Point, point2: Point, point3: Point) -> float:
    """Return the angle (degrees) at point2 formed by point1–point2–point3."""
    ax, ay = point1
    bx, by = point2
    cx, cy = point3

    radians = math.atan2(cy - by, cx - bx) - math.atan2(ay - by, ax - bx)
    angle = abs(math.degrees(radians))
    if angle > 180.0:
        angle = 360.0 - angle
    return angle


def as_frames(landmarks: Any) -> list[FrameLandmarks]:
    """Normalize input into a list of per-frame landmark dicts."""
    if landmarks is None:
        return []
    if isinstance(landmarks, list):
        frames: list[FrameLandmarks] = []
        for frame in landmarks:
            if not isinstance(frame, dict):
                continue
            # Step 4 pose_data shape: {frame_number, timestamp, landmarks:{...}}
            if "landmarks" in frame and isinstance(frame["landmarks"], dict):
                frames.append(frame["landmarks"])
            elif any(isinstance(v, dict) and "x" in v for v in frame.values()):
                frames.append(frame)
        return frames
    if isinstance(landmarks, dict):
        if "frames" in landmarks and isinstance(landmarks["frames"], list):
            return as_frames(landmarks["frames"])
        if any(isinstance(v, dict) and "x" in v for v in landmarks.values()):
            return [landmarks]
    return []


def xy(landmarks: FrameLandmarks, name: str) -> Point | None:
    point = landmarks.get(name)
    if not point:
        return None
    return float(point["x"]), float(point["y"])


def xyz(landmarks: FrameLandmarks, name: str) -> Point3 | None:
    point = landmarks.get(name)
    if not point:
        return None
    return float(point["x"]), float(point["y"]), float(point.get("z", 0.0))


def dist3(a: Point3, b: Point3) -> float:
    """3D Euclidean distance. Use this (not x-only) for left/right body-width
    measurements (shoulder width, foot spacing) — from a side camera angle
    the left/right pair sits almost inline with the lens, so their on-screen
    x-difference collapses toward zero even though the real 3D distance is
    normal, blowing up anything divided by it."""
    return math.dist(a, b)


def set_clip_shooting_side(side: str | None) -> None:
    """Lock shooting side for the current analysis (or clear with None)."""
    global _clip_shooting_side
    if side in ("left", "right"):
        _clip_shooting_side = side
    else:
        _clip_shooting_side = None


def get_clip_shooting_side() -> str | None:
    return _clip_shooting_side


def resolve_clip_shooting_side(frames: Sequence[FrameLandmarks]) -> str:
    """
    Stable shooting side for a whole clip via visibility-weighted votes.

    Prefers the wrist that rides higher (smaller y) most of the time, with a
    small deadband so tiny MediaPipe jitter doesn't flip the vote.
    """
    votes = {"left": 0.0, "right": 0.0}
    for frame in frames:
        left = xy(frame, "left_wrist")
        right = xy(frame, "right_wrist")
        lv = float((frame.get("left_wrist") or {}).get("visibility") or 0.0)
        rv = float((frame.get("right_wrist") or {}).get("visibility") or 0.0)
        if left and right:
            if right[1] < left[1] - 0.012:
                votes["right"] += max(rv, 0.25)
            elif left[1] < right[1] - 0.012:
                votes["left"] += max(lv, 0.25)
            elif rv >= lv:
                votes["right"] += max(rv, 0.15)
            else:
                votes["left"] += max(lv, 0.15)
        elif right:
            votes["right"] += max(rv, 0.25)
        elif left:
            votes["left"] += max(lv, 0.25)
    return "right" if votes["right"] >= votes["left"] else "left"


def shooting_side(frame: FrameLandmarks) -> str:
    """Return clip-locked side when set; else higher wrist on this frame."""
    if _clip_shooting_side in ("left", "right"):
        return _clip_shooting_side
    left = xy(frame, "left_wrist")
    right = xy(frame, "right_wrist")
    if left and right:
        return "right" if right[1] <= left[1] else "left"
    if right:
        return "right"
    return "left"


def side_points(
    frame: FrameLandmarks,
    side: str,
    joints: Sequence[str],
) -> list[Point] | None:
    points: list[Point] = []
    for joint in joints:
        point = xy(frame, f"{side}_{joint}")
        if point is None:
            return None
        points.append(point)
    return points


def status_from_score(score: int, pass_at: int = 80, warn_at: int = 65) -> str:
    if score >= pass_at:
        return "PASS"
    if score >= warn_at:
        return "WARN"
    return "FAIL"


def elbow_flare(
    shoulder: Point,
    elbow: Point,
    wrist: Point,
) -> float:
    """Horizontal distance of elbow from the shoulder→wrist line."""
    sx, sy = shoulder
    ex, ey = elbow
    wx, wy = wrist
    dx, dy = wx - sx, wy - sy
    length = math.hypot(dx, dy)
    if length < 1e-6:
        return abs(ex - sx)
    return abs(dy * ex - dx * ey + wx * sy - wy * sx) / length


def bend_from_standing(joint_angle: float) -> float:
    """Convert interior joint angle to bend degrees from a straight standing leg."""
    return max(0.0, 180.0 - float(joint_angle))


def make_category(
    *,
    category: str,
    score: int,
    measurement: str,
    issue: str = "",
    correction: str = "",
    timestamp: str = "00:00",
    seconds: float = 0.0,
    highlight: list[str] | None = None,
    confidence: float | None = None,
    phase: str | None = None,
    phase_key: str | None = None,
    playback_speed: float | None = None,
    auto_play: bool | None = None,
    features: dict[str, float] | None = None,
) -> dict[str, Any]:
    """Standard biomechanics category payload."""
    from biomechanics_config import color_for_status, status_from_score

    score_i = int(max(0, min(100, score)))
    status = status_from_score(score_i)
    payload: dict[str, Any] = {
        "category": category,
        "score": score_i,
        "status": status,
        "color": color_for_status(status),
        "measurement": measurement,
        "issue": issue or ("Solid mechanics" if status == "PASS" else "Needs work"),
        "correction": correction
        or ("Keep repeating this form" if status == "PASS" else "Adjust and retry"),
        "timestamp": timestamp,
        "seconds": float(seconds),
        "highlight": highlight or [],
    }
    if confidence is not None:
        payload["confidence"] = round(float(confidence), 3)
    if phase is not None:
        payload["phase"] = phase
    if phase_key is not None:
        payload["phase_key"] = phase_key
    if playback_speed is not None:
        payload["playback_speed"] = float(playback_speed)
    if auto_play is not None:
        payload["auto_play"] = bool(auto_play)
    if features:
        payload["features"] = {
            str(k): round(float(v), 4) for k, v in features.items()
        }
    return payload


def resolve_phases(
    landmarks: Any,
    fps: float,
    phases: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Reuse a shared phase map when provided; otherwise detect once."""
    if phases is not None:
        return phases
    from shot_phases import detect_shot_phases

    return detect_shot_phases(landmarks, fps=fps)
