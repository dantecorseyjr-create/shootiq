"""Balance biomechanics — scored from Gather through Landing."""

from __future__ import annotations

from typing import Any

import numpy as np

import biomechanics_config as cfg
from personalization import window_confidence
from pose_utils import as_frames, make_category, resolve_phases, xy
from shot_phases import frames_between


def analyze_balance(
    landmarks: Any,
    fps: float = 30.0,
    phases: dict[str, Any] | None = None,
    timestamp: float | None = None,
) -> dict[str, Any]:
    """
    Balance across the full shot motion:
    - body lean
    - sideways drift (torso vs hips / ankles)
    - hip level through gather → landing
    """
    frames = as_frames(landmarks)
    phases = resolve_phases(landmarks, fps, phases)
    window = frames_between(frames, phases, "gather", "landing", pad=0)
    if not window:
        window = frames

    # Seek to gather keyframe for coaching review.
    seek = phases["gather"]

    hip_levels: list[float] = []
    sideways: list[float] = []
    leans: list[float] = []
    drift_dirs: list[float] = []

    for frame in window:
        l_hip, r_hip = xy(frame, "left_hip"), xy(frame, "right_hip")
        l_sh, r_sh = xy(frame, "left_shoulder"), xy(frame, "right_shoulder")
        l_ankle, r_ankle = xy(frame, "left_ankle"), xy(frame, "right_ankle")
        if l_hip and r_hip:
            hip_levels.append(abs(l_hip[1] - r_hip[1]))
        if l_hip and r_hip and l_sh and r_sh:
            mid_hip_x = (l_hip[0] + r_hip[0]) / 2
            mid_sh_x = (l_sh[0] + r_sh[0]) / 2
            sideways.append(abs(mid_sh_x - mid_hip_x))
            drift_dirs.append(mid_sh_x - mid_hip_x)
            if l_ankle and r_ankle:
                mid_ankle_x = (l_ankle[0] + r_ankle[0]) / 2
                leans.append(
                    abs(mid_sh_x - mid_ankle_x) - abs(mid_hip_x - mid_ankle_x)
                )

    stamp = seek["timestamp"]
    secs = float(seek["seconds"])
    if timestamp is not None:
        secs = float(timestamp)

    highlight = ["hip", "torso", "shoulder", "ankle"]
    conf = window_confidence(window, ["hip", "shoulder", "ankle"])

    if not hip_levels and not sideways:
        return make_category(
            category="Balance",
            score=0,
            measurement="Balance landmarks not detected",
            issue="Could not measure balance through the shot",
            correction="Face the camera so hips and shoulders are visible",
            timestamp=stamp,
            seconds=secs,
            highlight=highlight,
            phase="Gather",
            phase_key="gather",
            playback_speed=0.5,
            auto_play=True,
            confidence=min(conf, 0.25),
        )

    hip_level = float(np.mean(hip_levels)) if hip_levels else 0.05
    tilt = float(np.mean(sideways)) if sideways else 0.05
    lean = float(np.mean(leans)) if leans else 0.0
    drift = float(np.mean(drift_dirs)) if drift_dirs else 0.0

    score = 92
    issues: list[str] = []
    corrections: list[str] = []

    if lean > cfg.BACKWARD_LEAN_WARN:
        score -= 24
        issues.append("Leaning backward through the shot")
        corrections.append("Stay stacked over your base from gather to landing")
    elif lean > cfg.BACKWARD_LEAN_PASS:
        score -= 10
        issues.append("Slight backward lean through the motion")

    if tilt > cfg.TORSO_TILT_WARN:
        score -= 22
        direction = "left" if drift < 0 else "right"
        issues.append(f"Body drifting {direction} from gather to landing")
        corrections.append("Keep shoulders stacked over hips and feet")
    elif tilt > cfg.TORSO_TILT_PASS:
        score -= 10
        issues.append("Slight sideways drift through the shot")

    if hip_level > cfg.HIP_LEVEL_WARN:
        score -= 14
        issues.append("Hips are uneven through the shot")
        corrections.append("Level your hips and land centered")
    elif hip_level > cfg.HIP_LEVEL_PASS:
        score -= 6
        issues.append("Hips drift slightly out of level")

    score = int(np.clip(score, 35, 100))
    if not issues:
        issue = "Balanced base from gather through landing"
        correction = "Stay tall and stacked over your feet"
    else:
        issue = issues[0]
        correction = corrections[0] if corrections else "Stay balanced over your base"

    return make_category(
        category="Balance",
        score=score,
        measurement=(
            f"Hip level {hip_level:.3f}, sideways {tilt:.3f}, lean {lean:.3f}"
        ),
        issue=issue,
        correction=correction,
        timestamp=stamp,
        seconds=secs,
        highlight=highlight,
        phase="Gather",
        phase_key="gather",
        playback_speed=0.5,
        auto_play=True,
        confidence=conf,
        features={
            "hip_level": hip_level,
            "torso_tilt": tilt,
            "backward_lean": lean,
        },
    )


def analyze_hips_core(
    landmarks: Any,
    fps: float = 30.0,
    phases: dict[str, Any] | None = None,
    timestamp: float | None = None,
) -> dict[str, Any]:
    return analyze_balance(landmarks, fps=fps, phases=phases, timestamp=timestamp)


def analyze_head(
    landmarks: Any,
    fps: float = 30.0,
    phases: dict[str, Any] | None = None,
    timestamp: float | None = None,
) -> dict[str, Any]:
    """Optional head stability check (not part of primary average)."""
    frames = as_frames(landmarks)
    phases = resolve_phases(landmarks, fps, phases)
    window = frames_between(frames, phases, "set_point", "release", pad=1)
    seek = phases["release"]

    nose_xy = [xy(f, "nose") for f in window]
    nose_xy = [p for p in nose_xy if p]
    stamp = seek["timestamp"]
    secs = float(seek["seconds"])
    if timestamp is not None:
        secs = float(timestamp)

    if len(nose_xy) < 2:
        return make_category(
            category="Head Position",
            score=70,
            measurement="Head landmarks limited",
            issue="Head tracking confidence is limited",
            correction="Keep your face visible toward the rim",
            timestamp=stamp,
            seconds=secs,
            highlight=["torso"],
            confidence=0.3,
            phase="Release",
            phase_key="release",
        )

    xs = np.array([p[0] for p in nose_xy], dtype=float)
    ys = np.array([p[1] for p in nose_xy], dtype=float)
    motion = float(np.std(xs) + np.std(ys))

    if motion <= cfg.HEAD_STABILITY_PASS:
        score, issue, confidence = 90, "Head stays quiet through release", 0.7
        correction = "Keep eyes soft on the rim"
    elif motion <= cfg.HEAD_STABILITY_WARN:
        score, issue, confidence = 72, "Slight head movement near release", 0.55
        correction = "Quiet your head as you rise into the shot"
    else:
        score, issue, confidence = 55, "Head movement detected during release", 0.5
        correction = "Freeze your head and eyes on the rim through the finish"

    return make_category(
        category="Head Position",
        score=score,
        measurement=f"Head motion index {motion:.3f}",
        issue=issue,
        correction=correction,
        timestamp=stamp,
        seconds=secs,
        highlight=["torso"],
        confidence=confidence,
        phase="Release",
        phase_key="release",
    )
