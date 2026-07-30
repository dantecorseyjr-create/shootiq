"""Set Point biomechanics — elbow angle, forearm angle, wrist position."""

from __future__ import annotations

from typing import Any

import numpy as np

import biomechanics_config as cfg
from personalization import window_confidence
from pose_eval import elbow_angle, forearm_angle_from_vertical, wrist_position_vs_elbow
from pose_utils import as_frames, make_category, resolve_phases
from shot_phases import phase_window


def analyze_elbow(
    landmarks: Any,
    fps: float = 30.0,
    phases: dict[str, Any] | None = None,
    timestamp: float | None = None,
) -> dict[str, Any]:
    """Set Point phase only: elbow / forearm / wrist set under the ball."""
    frames = as_frames(landmarks)
    phases = resolve_phases(landmarks, fps, phases)
    # Prefer set_point; fall back to legacy upward_motion alias via normalize.
    window = phase_window(frames, phases, "set_point", pad=1)
    if not window and "upward_motion" in phases:
        window = phase_window(frames, phases, "upward_motion", pad=1)
    seek = phases.get("set_point") or phases.get("upward_motion") or phases["release"]

    elbows: list[float] = []
    forearms: list[float] = []
    wrists: list[float] = []
    for frame in window:
        e = elbow_angle(frame)
        f_ang = forearm_angle_from_vertical(frame)
        w = wrist_position_vs_elbow(frame)
        if e is not None:
            elbows.append(e)
        if f_ang is not None:
            forearms.append(f_ang)
        if w is not None:
            wrists.append(w)

    stamp = seek["timestamp"]
    secs = float(seek["seconds"] if timestamp is None else timestamp)
    highlight = ["elbow", "forearm", "wrist", "shoulder"]
    conf = window_confidence(window, ["elbow", "wrist", "shoulder"])

    if not elbows:
        return make_category(
            category="Set Point",
            score=0,
            measurement="Set point not detected",
            issue="Could not track the shooting arm at set point",
            correction="Keep your shooting arm fully visible as you rise",
            timestamp=stamp,
            seconds=secs,
            highlight=highlight,
            phase="Set Point",
            phase_key="set_point",
            playback_speed=0.5,
            auto_play=True,
            confidence=min(conf, 0.25),
        )

    # Near ~90° set — use the most "set-like" (closest to 90) sample.
    set_angle = float(min(elbows, key=lambda a: abs(a - cfg.ELBOW_SET_TARGET)))
    forearm = float(np.mean(forearms)) if forearms else 0.0
    wrist_delta = float(np.mean(wrists)) if wrists else 0.0

    score = 94
    issues: list[str] = []
    corrections: list[str] = []
    slo, shi = cfg.ELBOW_SET_PASS
    swlo, swhi = cfg.ELBOW_SET_WARN

    if not (slo <= set_angle <= shi):
        flare = abs(set_angle - cfg.ELBOW_SET_TARGET)
        if swlo <= set_angle <= swhi:
            score -= 12
            issues.append(
                f"Your elbow opens about {flare:.0f}° from the ideal under-ball "
                f"set (measured {set_angle:.0f}°, target ~90°)"
            )
            corrections.append(
                "Keep your shooting elbow under the ball — elbow points toward the rim"
            )
        else:
            score -= 22
            issues.append(
                f"Your elbow alignment breaks at set — {set_angle:.0f}° instead of ~90°. "
                f"That flare costs power and consistency"
            )
            corrections.append(
                "Pause at set point: elbow under the ball near 90°, then push up"
            )

    if forearm > cfg.FOREARM_VERTICAL_WARN:
        score -= 18
        issues.append(
            f"Your forearm is {forearm:.0f}° off vertical at set, so the arm path "
            f"starts outside the shot line"
        )
        corrections.append(
            "Stack wrist over elbow over hip — forearm more vertical at set"
        )
    elif forearm > cfg.FOREARM_VERTICAL_PASS:
        score -= 8
        issues.append(
            f"Forearm tilts slightly at set ({forearm:.0f}° from vertical)"
        )
        corrections.append("Tighten the set so the forearm stays closer to vertical")

    if wrist_delta > cfg.WRIST_ABOVE_ELBOW_WARN:
        score -= 16
        issues.append(
            "Your wrist sits too low relative to the elbow at set, forcing a hitch into release"
        )
        corrections.append("Keep the wrist above the elbow line before you extend")
    elif wrist_delta > cfg.WRIST_ABOVE_ELBOW_PASS:
        score -= 8
        issues.append("Wrist is slightly low at set point")
        corrections.append("Raise the wrist onto the elbow line at set")

    score = int(np.clip(score, 30, 100))
    if not issues:
        issue = "Clean set point — elbow, forearm, and wrist are stacked under the ball"
        correction = "Hold this set on every shot before you extend"
    else:
        issue = issues[0]
        correction = corrections[0] if corrections else (
            "Keep your shooting elbow under the ball and push straight to the rim"
        )

    return make_category(
        category="Set Point",
        score=score,
        measurement=(
            f"Elbow {set_angle:.0f}°, forearm {forearm:.0f}° from vertical, "
            f"wristΔ {wrist_delta:.3f}"
        ),
        issue=issue,
        correction=correction,
        timestamp=stamp,
        seconds=secs,
        highlight=highlight,
        phase="Set Point",
        phase_key="set_point",
        playback_speed=0.5,
        auto_play=True,
        confidence=conf,
        features={
            "elbow_set_angle": set_angle,
            "forearm_from_vertical_deg": forearm,
            "wrist_vs_elbow": wrist_delta,
        },
    )


analyze_set_point = analyze_elbow
