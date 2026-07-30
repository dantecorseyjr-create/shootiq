"""Load biomechanics — knee angle, hip position, center of mass."""

from __future__ import annotations

from typing import Any

import numpy as np

import biomechanics_config as cfg
from personalization import window_confidence
from pose_eval import center_of_mass_offset, hip_height, knee_joint_and_bend
from pose_utils import as_frames, make_category, resolve_phases
from shot_phases import phase_window


def analyze_knees(
    landmarks: Any,
    fps: float = 30.0,
    phases: dict[str, Any] | None = None,
    timestamp: float | None = None,
) -> dict[str, Any]:
    """Load phase only: knee angle + hip position + COM over base."""
    frames = as_frames(landmarks)
    phases = resolve_phases(landmarks, fps, phases)
    window = phase_window(frames, phases, "knee_load", pad=2)
    seek = phases["knee_load"]
    stance_window = phase_window(frames, phases, "setup", pad=0)

    bends: list[float] = []
    angles: list[float] = []
    hips: list[float] = []
    coms: list[float] = []
    for frame in window:
        kn = knee_joint_and_bend(frame)
        hh = hip_height(frame)
        com = center_of_mass_offset(frame)
        if kn is not None:
            angles.append(kn[0])
            bends.append(kn[1])
        if hh is not None:
            hips.append(hh)
        if com is not None:
            coms.append(com)

    stance_hips = [
        h for h in (hip_height(f) for f in stance_window) if h is not None
    ]
    baseline_hip = float(np.median(stance_hips)) if stance_hips else None

    stamp = seek["timestamp"]
    secs = float(seek["seconds"] if timestamp is None else timestamp)
    highlight = ["knee", "hip", "ankle", "torso"]
    conf = window_confidence(window, ["knee", "hip", "ankle"])

    if not bends:
        return make_category(
            category="Load",
            score=0,
            measurement="Load landmarks not detected",
            issue="Could not measure knee / hip at load",
            correction="Keep legs and hips fully visible",
            timestamp=stamp,
            seconds=secs,
            highlight=highlight,
            phase="Load",
            phase_key="knee_load",
            playback_speed=0.5,
            auto_play=False,
            confidence=min(conf, 0.25),
        )

    bend = float(np.max(bends))
    angle = float(np.min(angles)) if angles else 180.0 - bend
    hip = float(np.mean(hips)) if hips else 0.0
    com = float(np.mean(coms)) if coms else 0.0
    hip_drop = (hip - baseline_hip) if baseline_hip is not None else 0.0

    score = 92
    issues: list[str] = []
    corrections: list[str] = []
    lo, hi = cfg.KNEE_BEND_PASS
    wlo, whi = cfg.KNEE_BEND_WARN

    if lo <= bend <= hi:
        pass
    elif bend < wlo:
        score -= 30
        issues.append(f"Knee angle too straight at load ({angle:.0f}° joint)")
        corrections.append("Sit into an athletic load before rising")
    elif bend > whi:
        score -= 24
        issues.append("Knee bend too deep at load")
        corrections.append("Use a controlled athletic bend, then explode upward")
    elif wlo <= bend < lo:
        score -= 14
        issues.append("Knee bend is shallow at maximum load")
        corrections.append("Lower your hips more before shooting")
    else:
        score -= 12
        issues.append("Knee bend slightly outside the ideal load window")

    if baseline_hip is not None and hip_drop < cfg.HIP_DROP_WARN:
        score -= 12
        issues.append("Hips stay too high — not enough load in the hips")
        corrections.append("Drop your hips into the load")
    elif baseline_hip is not None and hip_drop < cfg.HIP_DROP_PASS:
        score -= 6
        issues.append("Hip drop is light at load")

    if com > cfg.COM_OFFSET_WARN:
        score -= 16
        issues.append("Center of mass is outside your base at load")
        corrections.append("Keep your weight stacked over mid-foot at the bottom")
    elif com > cfg.COM_OFFSET_PASS:
        score -= 8
        issues.append("Center of mass drifts slightly at load")

    score = int(np.clip(score, 35, 100))
    if not issues:
        issue = "Strong load — knee angle, hips, and COM look athletic"
        correction = "Keep loading like this before every rise"
    else:
        issue = issues[0]
        correction = corrections[0] if corrections else (
            "Load the legs with hips over mid-foot, about 60° of knee bend"
        )

    return make_category(
        category="Load",
        score=score,
        measurement=(
            f"Knee bend {bend:.0f}° (joint {angle:.0f}°), "
            f"hip drop {hip_drop:.3f}, COM offset {com:.3f}"
        ),
        issue=issue,
        correction=correction,
        timestamp=stamp,
        seconds=secs,
        highlight=highlight,
        phase="Load",
        phase_key="knee_load",
        playback_speed=0.5,
        auto_play=False,
        confidence=conf,
        features={
            "knee_bend_deg": bend,
            "knee_joint_angle": angle,
            "hip_drop": hip_drop,
            "com_offset": com,
        },
    )


analyze_load = analyze_knees
