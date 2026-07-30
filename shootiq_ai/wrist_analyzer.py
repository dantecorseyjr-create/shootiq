"""Wrist load and snap biomechanics."""

from __future__ import annotations

from typing import Any

import numpy as np

import biomechanics_config as cfg
from pose_utils import as_frames, make_category, resolve_phases, shooting_side, xy
from shot_phases import detect_shot_phases


def analyze_wrist(landmarks: Any, fps: float = 30.0) -> dict[str, Any]:
    frames = as_frames(landmarks)
    phases = detect_shot_phases(frames, fps=fps)
    setup_i = int(phases["setup"]["frame"])
    release_i = int(phases["release"]["frame"])
    follow_i = int(phases["follow_through"]["frame"])

    def wrist_elbow_delta(index: int) -> float | None:
        if index < 0 or index >= len(frames):
            return None
        frame = frames[index]
        side = shooting_side(frame)
        wrist = xy(frame, f"{side}_wrist")
        elbow = xy(frame, f"{side}_elbow")
        if not wrist or not elbow:
            return None
        # Positive when wrist is below elbow (loaded); negative when above.
        return wrist[1] - elbow[1]

    load = wrist_elbow_delta(setup_i)
    mid = wrist_elbow_delta(release_i)
    finish = wrist_elbow_delta(min(follow_i, len(frames) - 1))

    if load is None and mid is None:
        return make_category(
            category="Wrist",
            score=0,
            measurement="Wrist motion not detected",
            issue="Could not track wrist",
            correction="Keep shooting hand visible through the release",
            timestamp=phases["release"]["timestamp"],
            seconds=phases["release"]["seconds"],
            highlight=["wrist"],
        )

    load_v = float(load if load is not None else 0.0)
    mid_v = float(mid if mid is not None else load_v)
    finish_v = float(finish if finish is not None else mid_v)
    # Snap proxy: wrist moves upward (y decreases) from set → release/follow.
    snap = load_v - min(mid_v, finish_v)

    score = 88
    issues: list[str] = []
    if load_v < 0:
        score -= 10
        issues.append("Wrist is not loaded backward at set point")
    if snap < cfg.WRIST_SNAP_WARN:
        score -= 25
        issues.append("No wrist snap detected")
    elif snap < cfg.WRIST_SNAP_PASS:
        score -= 12
        issues.append("Wrist snap is weak through release")

    score = int(np.clip(score, 40, 100))
    if not issues:
        issue = "Clean wrist load and snap"
        correction = "Keep finishing with a relaxed downward snap"
    else:
        issue = issues[0]
        correction = "Load the wrist at set, then snap forward on release"

    return make_category(
        category="Wrist",
        score=score,
        measurement=f"Wrist snap delta {snap:.3f} (load {load_v:.3f})",
        issue=issue,
        correction=correction,
        timestamp=phases["release"]["timestamp"],
        seconds=phases["release"]["seconds"],
        highlight=["wrist"],
    )


def analyze_hand_position(
    landmarks: Any,
    fps: float = 30.0,
    phases: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    Ball / guide-hand position proxy from Pose wrists only.

    Full hand tracking (MediaPipe Hands) is a future upgrade.
    """
    frames = as_frames(landmarks)
    # Reuse shared phase map — never re-detect without timestamps.
    phases = resolve_phases(landmarks, fps, phases)
    release_i = int(phases["release"]["frame"])
    frame = frames[min(release_i, len(frames) - 1)] if frames else {}
    side = shooting_side(frame) if frame else "right"
    other = "left" if side == "right" else "right"
    shoot = xy(frame, f"{side}_wrist") if frame else None
    guide = xy(frame, f"{other}_wrist") if frame else None
    stamp = phases["release"]["timestamp"]
    secs = float(phases["release"]["seconds"])

    if not shoot or not guide:
        return make_category(
            category="Ball Position",
            score=70,
            measurement="Pose-only ball/hand proxy (Hands model not enabled)",
            issue="Ball position detail limited without MediaPipe Hands",
            correction="Keep both wrists visible through the set and release",
            timestamp=stamp,
            seconds=secs,
            highlight=["wrist"],
            phase="Set Point",
            phase_key="set_point",
            playback_speed=0.5,
            auto_play=True,
            confidence=0.35,
        )

    # Guide hand should sit beside (larger |dx|) and not far above shooting wrist.
    dx = abs(guide[0] - shoot[0])
    dy = guide[1] - shoot[1]
    score = 82
    issue = "Ball path looks centered at release"
    correction = "Keep guide hand soft on the side of the ball"
    if dx < 0.04:
        score = 62
        issue = "Guide hand crowding the ball path"
        correction = "Keep guide hand on the side — avoid pushing across the ball"
    elif dy < -0.08:
        score = 68
        issue = "Guide hand riding too high over the ball"
        correction = "Drop the guide hand to the side before release"

    return make_category(
        category="Ball Position",
        score=score,
        measurement=f"Guide/shoot wrist offset dx={dx:.3f}, dy={dy:.3f}",
        issue=issue,
        correction=correction,
        timestamp=stamp,
        seconds=secs,
        highlight=["wrist"],
        phase="Set Point",
        phase_key="set_point",
        playback_speed=0.5,
        auto_play=True,
        confidence=0.45,
    )
