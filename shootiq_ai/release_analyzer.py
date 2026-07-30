"""Release biomechanics — elbow extension, wrist snap, body alignment."""

from __future__ import annotations

from typing import Any

import numpy as np

import biomechanics_config as cfg
from personalization import window_confidence
from pose_eval import body_alignment, elbow_angle, wrist_position_vs_elbow
from pose_utils import as_frames, make_category, resolve_phases
from shot_phases import phase_window


def analyze_release(
    landmarks: Any,
    fps: float = 30.0,
    phases: dict[str, Any] | None = None,
    timestamp: float | None = None,
) -> dict[str, Any]:
    """Release phase: extension through the ball, wrist snap, stacked body."""
    frames = as_frames(landmarks)
    phases = resolve_phases(landmarks, fps, phases)
    window = phase_window(frames, phases, "release", pad=1)
    seek = phases["release"]

    release_i = int(seek.get("frame", 0))
    follow_start = int(
        phases.get("follow_through", {}).get("start_frame", release_i + 1)
    )
    follow_end = int(
        phases.get("follow_through", {}).get("end_frame", follow_start)
    )

    extensions: list[float] = []
    aligns: list[float] = []
    for frame in window:
        e = elbow_angle(frame)
        a = body_alignment(frame)
        if e is not None:
            extensions.append(e)
        if a is not None:
            aligns.append(a)

    # Wrist snap: wrist drops relative to elbow from release into early follow.
    wrist_at_release: list[float] = []
    wrist_after: list[float] = []
    for frame in window:
        w = wrist_position_vs_elbow(frame)
        if w is not None:
            wrist_at_release.append(w)
    for i in range(follow_start, min(len(frames), follow_end + 1)):
        w = wrist_position_vs_elbow(frames[i])
        if w is not None:
            wrist_after.append(w)

    stamp = seek["timestamp"]
    secs = float(seek["seconds"] if timestamp is None else timestamp)
    highlight = ["elbow", "wrist", "shoulder", "hip", "torso"]
    conf = window_confidence(window, ["elbow", "wrist", "shoulder", "hip"])

    if not extensions:
        return make_category(
            category="Release",
            score=0,
            measurement="Release not detected",
            issue="Could not measure release mechanics",
            correction="Keep shooting arm and torso in frame through release",
            timestamp=stamp,
            seconds=secs,
            highlight=highlight,
            phase="Release",
            phase_key="release",
            playback_speed=0.5,
            auto_play=True,
            confidence=min(conf, 0.25),
        )

    extension = float(np.max(extensions))
    align = float(np.mean(aligns)) if aligns else 0.0
    wr0 = float(np.mean(wrist_at_release)) if wrist_at_release else 0.0
    wr1 = float(np.mean(wrist_after)) if wrist_after else wr0
    wrist_snap = wr1 - wr0  # positive = wrist flexed down after release

    score = 92
    issues: list[str] = []
    corrections: list[str] = []

    if extension < cfg.ELBOW_RELEASE_WARN_MIN:
        score -= 26
        issues.append(
            f"Your release is late relative to arm extension — elbow only reaches "
            f"{extension:.0f}° as the ball leaves (need ~{cfg.ELBOW_RELEASE_PASS_MIN:.0f}°+)"
        )
        corrections.append(
            "Start the wrist snap earlier as you leave the dip so the elbow finishes "
            "through the ball near jump peak"
        )
    elif extension < cfg.ELBOW_RELEASE_PASS_MIN:
        score -= 12
        issues.append(
            f"Elbow extension is incomplete at release ({extension:.0f}°) — "
            f"legs finish before the arm fully unlocks"
        )
        corrections.append(
            "Stay long through the elbow and release near the top of your jump"
        )

    if wrist_snap < cfg.WRIST_SNAP_WARN:
        score -= 20
        issues.append(
            "Wrist snap is missing at release — the ball leaves without a clean fingertip finish"
        )
        corrections.append(
            "Snap the wrist through the ball and hold the goose-neck until it hits rim"
        )
    elif wrist_snap < cfg.WRIST_SNAP_PASS:
        score -= 10
        issues.append("Wrist snap is light — finish is cutting short at release")
        corrections.append("Exaggerate the fingertip snap and hold the finish higher")

    if align > cfg.RELEASE_ALIGN_WARN:
        score -= 16
        issues.append(
            "Body alignment breaks at release — shoulders/hips drift off the shot line"
        )
        corrections.append(
            "Stay stacked — shoulders over hips over feet — through the release"
        )
    elif align > cfg.RELEASE_ALIGN_PASS:
        score -= 8
        issues.append("Slight alignment drift at release")
        corrections.append("Quiet the torso and finish on balance")

    score = int(np.clip(score, 30, 100))
    if not issues:
        issue = "Strong release — extension, wrist snap, and alignment look clean"
        correction = "Repeat this release finish every shot"
    else:
        issue = issues[0]
        correction = corrections[0] if corrections else (
            "Release near jump peak with a full elbow extension and crisp wrist snap"
        )

    return make_category(
        category="Release",
        score=score,
        measurement=(
            f"Elbow extension {extension:.0f}°, "
            f"wrist snap {wrist_snap:.3f}, "
            f"alignment {align:.3f}"
        ),
        issue=issue,
        correction=correction,
        timestamp=stamp,
        seconds=secs,
        highlight=highlight,
        phase="Release",
        phase_key="release",
        playback_speed=0.5,
        auto_play=True,
        confidence=conf,
        features={
            "elbow_release_angle": extension,
            "wrist_snap": wrist_snap,
            "body_alignment": align,
        },
    )
