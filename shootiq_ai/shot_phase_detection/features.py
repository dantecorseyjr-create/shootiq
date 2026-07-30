"""Temporal motion features for shot-phase classification.

Features are derivatives / velocities over time — not static joint angles
used as hard gates. Angle levels may appear as context channels only.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

from pose_utils import (
    bend_from_standing,
    calculate_angle,
    shooting_side,
    side_points,
    xy,
)


@dataclass
class TemporalFeatureSeries:
    """Aligned per-sample motion channels (length N)."""

    timestamps: np.ndarray  # seconds
    video_frames: np.ndarray  # int
    dt: np.ndarray  # seconds between samples (same length, dt[0]=median)

    # Context levels (not used as sole classifiers)
    knee_flexion: np.ndarray  # bend-from-standing degrees
    elbow_extension: np.ndarray  # joint angle degrees (larger = more extended)

    # Temporal / velocity channels (primary for classification)
    knee_flex_vel: np.ndarray  # deg/s  (+ = flexing / loading)
    elbow_ext_vel: np.ndarray  # deg/s  (+ = extending)
    wrist_vy: np.ndarray  # norm-units/s  (+ = rising on screen)
    wrist_vx: np.ndarray
    hip_vy: np.ndarray  # (+ = rising)
    shoulder_vy: np.ndarray
    ankle_vy: np.ndarray

    # Derived helpers
    wrist_y: np.ndarray
    hip_y: np.ndarray
    ankle_y: np.ndarray

    @property
    def n(self) -> int:
        return int(self.timestamps.shape[0])

    def to_training_matrix(self) -> np.ndarray:
        """NxF matrix for future supervised models."""
        return np.column_stack(
            [
                self.knee_flex_vel,
                self.elbow_ext_vel,
                self.wrist_vy,
                self.wrist_vx,
                self.hip_vy,
                self.shoulder_vy,
                self.ankle_vy,
                self.knee_flexion,
                self.elbow_extension,
                self.wrist_y,
            ]
        )

    def feature_names(self) -> list[str]:
        return [
            "knee_flex_vel",
            "elbow_ext_vel",
            "wrist_vy",
            "wrist_vx",
            "hip_vy",
            "shoulder_vy",
            "ankle_vy",
            "knee_flexion",
            "elbow_extension",
            "wrist_y",
        ]


def unpack_pose_frames(
    landmarks: Any,
    fps: float,
) -> tuple[list[dict[str, dict[str, float]]], np.ndarray, np.ndarray]:
    """Public unpacker: (frames, timestamps, video_frame_numbers)."""
    if landmarks is None:
        return [], np.zeros(0), np.zeros(0, dtype=int)

    if isinstance(landmarks, dict) and isinstance(landmarks.get("frames"), list):
        landmarks = landmarks["frames"]

    if not isinstance(landmarks, list) or not landmarks:
        return [], np.zeros(0), np.zeros(0, dtype=int)

    frames: list[dict[str, dict[str, float]]] = []
    timestamps: list[float] = []
    video_frames: list[int] = []
    safe_fps = fps if fps and fps > 1 else 30.0

    for i, item in enumerate(landmarks):
        if not isinstance(item, dict):
            continue
        if "landmarks" in item and isinstance(item["landmarks"], dict):
            frames.append(item["landmarks"])
            timestamps.append(float(item.get("timestamp", i / safe_fps)))
            video_frames.append(int(item.get("frame_number", i)))
        elif any(isinstance(v, dict) and "x" in v for v in item.values()):
            frames.append(item)
            timestamps.append(i / safe_fps)
            video_frames.append(i)

    return frames, np.asarray(timestamps, dtype=float), np.asarray(video_frames, dtype=int)


def _fill_nan(values: np.ndarray) -> np.ndarray:
    out = values.astype(float).copy()
    if out.size == 0:
        return out
    idx = np.arange(out.size)
    good = np.isfinite(out)
    if not np.any(good):
        return np.zeros_like(out)
    if np.all(good):
        return out
    out[~good] = np.interp(idx[~good], idx[good], out[good])
    return out


def _smooth(values: np.ndarray, window: int) -> np.ndarray:
    if values.size == 0:
        return values
    w = max(1, int(window))
    if w == 1 or values.size < 3:
        return values
    kernel = np.ones(w, dtype=float) / w
    padded = np.pad(values, (w // 2, w - 1 - w // 2), mode="edge")
    return np.convolve(padded, kernel, mode="valid")


def _velocity(series: np.ndarray, timestamps: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Central-ish finite difference / real Δt (handles sample_every)."""
    n = series.size
    if n == 0:
        return np.zeros(0), np.zeros(0)
    if n == 1:
        return np.zeros(1), np.array([1.0 / 30.0])

    dt = np.diff(timestamps)
    dt = np.where(dt <= 1e-6, np.median(dt[dt > 1e-6]) if np.any(dt > 1e-6) else 1.0 / 30.0, dt)
    # Per-sample dt (forward-filled for last)
    dt_full = np.concatenate([dt, dt[-1:]])

    vel = np.zeros(n, dtype=float)
    vel[1:] = np.diff(series) / dt
    vel[0] = vel[1]
    return vel, dt_full


def extract_temporal_features(
    landmarks: Any,
    fps: float = 30.0,
    *,
    sample_every: int = 1,
    smooth_window: int | None = None,
) -> TemporalFeatureSeries | None:
    """
    Build motion feature series from pose landmarks over time.

    sample_every: original video stride (for documentation / training metadata).
    Timestamps on frames are authoritative for velocity scaling.
    """
    del sample_every  # timestamps already encode real time
    frames, timestamps, video_frames = unpack_pose_frames(landmarks, fps)
    n = len(frames)
    if n == 0:
        return None

    if timestamps.size != n:
        safe_fps = fps if fps and fps > 1 else 30.0
        timestamps = np.arange(n, dtype=float) / safe_fps
    if video_frames.size != n:
        video_frames = np.arange(n, dtype=int)

    knee = np.full(n, np.nan)
    elbow = np.full(n, np.nan)
    wrist_y = np.full(n, np.nan)
    wrist_x = np.full(n, np.nan)
    hip_y = np.full(n, np.nan)
    shoulder_y = np.full(n, np.nan)
    ankle_y = np.full(n, np.nan)

    for i, frame in enumerate(frames):
        side = shooting_side(frame)

        bends: list[float] = []
        for s in ("left", "right"):
            leg = side_points(frame, s, ("hip", "knee", "ankle"))
            if leg is not None:
                bends.append(
                    bend_from_standing(calculate_angle(leg[0], leg[1], leg[2]))
                )
        if bends:
            knee[i] = float(np.mean(bends))

        arm = side_points(frame, side, ("shoulder", "elbow", "wrist"))
        if arm is not None:
            elbow[i] = calculate_angle(arm[0], arm[1], arm[2])

        wrist = xy(frame, f"{side}_wrist")
        if wrist:
            wrist_x[i] = wrist[0]
            wrist_y[i] = wrist[1]

        l_hip, r_hip = xy(frame, "left_hip"), xy(frame, "right_hip")
        if l_hip and r_hip:
            hip_y[i] = (l_hip[1] + r_hip[1]) / 2
        elif l_hip or r_hip:
            hip_y[i] = (l_hip or r_hip)[1]

        l_sh, r_sh = xy(frame, "left_shoulder"), xy(frame, "right_shoulder")
        if l_sh and r_sh:
            shoulder_y[i] = (l_sh[1] + r_sh[1]) / 2
        elif l_sh or r_sh:
            shoulder_y[i] = (l_sh or r_sh)[1]

        l_an, r_an = xy(frame, "left_ankle"), xy(frame, "right_ankle")
        if l_an and r_an:
            ankle_y[i] = (l_an[1] + r_an[1]) / 2
        elif l_an or r_an:
            ankle_y[i] = (l_an or r_an)[1]

    # Smooth levels in sample space, then differentiate with real time.
    win = smooth_window if smooth_window is not None else max(3, int(round(fps / 10)))
    knee_s = _smooth(_fill_nan(knee), win)
    elbow_s = _smooth(_fill_nan(elbow), win)
    wrist_y_s = _smooth(_fill_nan(wrist_y), win)
    wrist_x_s = _smooth(_fill_nan(wrist_x), win)
    hip_s = _smooth(_fill_nan(hip_y), win)
    sh_s = _smooth(_fill_nan(shoulder_y), win)
    an_s = _smooth(_fill_nan(ankle_y), win)

    # Image y grows downward → rising motion = negative Δy.
    knee_vel, dt = _velocity(knee_s, timestamps)
    elbow_vel, _ = _velocity(elbow_s, timestamps)
    wrist_y_vel, _ = _velocity(wrist_y_s, timestamps)
    wrist_x_vel, _ = _velocity(wrist_x_s, timestamps)
    hip_vel, _ = _velocity(hip_s, timestamps)
    sh_vel, _ = _velocity(sh_s, timestamps)
    an_vel, _ = _velocity(an_s, timestamps)

    # Convert to "up is positive" for vertical channels.
    wrist_vy = -wrist_y_vel
    hip_vy = -hip_vel
    shoulder_vy = -sh_vel
    ankle_vy = -an_vel

    # Light smooth on velocities to reduce MediaPipe jitter.
    vwin = max(3, win // 2 * 2 + 1)
    return TemporalFeatureSeries(
        timestamps=timestamps,
        video_frames=video_frames,
        dt=dt,
        knee_flexion=knee_s,
        elbow_extension=elbow_s,
        knee_flex_vel=_smooth(knee_vel, vwin),
        elbow_ext_vel=_smooth(elbow_vel, vwin),
        wrist_vy=_smooth(wrist_vy, vwin),
        wrist_vx=_smooth(wrist_x_vel, vwin),
        hip_vy=_smooth(hip_vy, vwin),
        shoulder_vy=_smooth(shoulder_vy, vwin),
        ankle_vy=_smooth(ankle_vy, vwin),
        wrist_y=wrist_y_s,
        hip_y=hip_s,
        ankle_y=an_s,
    )
