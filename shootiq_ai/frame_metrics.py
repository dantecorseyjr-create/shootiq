"""Per-frame biomechanics series for Results timeline scrubbing.

Computed once during `/analyze` from saved pose frames — never re-run on seek.
"""

from __future__ import annotations

import math
from typing import Any

import numpy as np

import biomechanics_config as cfg
from pose_utils import (
    bend_from_standing,
    calculate_angle,
    elbow_flare,
    shooting_side,
    side_points,
    xy,
)
from shot_phase_detection.features import unpack_pose_frames
from shot_phases import (
    PHASE_LABELS,
    PHASE_ORDER,
    phase_name_for_index,
)

# Body parts evaluated during each shot phase (UI highlight chips).
PHASE_HIGHLIGHTS: dict[str, list[str]] = {
    "setup": ["ankle", "foot", "hip", "torso"],
    "gather": ["hip", "torso", "knee", "ankle"],
    "knee_load": ["knee", "hip", "ankle", "torso"],
    "set_point": ["elbow", "forearm", "wrist", "shoulder"],
    "release": ["elbow", "wrist", "shoulder", "hip", "torso"],
    "follow_through": ["elbow", "wrist", "shoulder", "hip", "torso"],
    "landing": ["ankle", "hip", "torso"],
}


def _band_color(
    value: float | None,
    *,
    pass_range: tuple[float, float] | None = None,
    warn_range: tuple[float, float] | None = None,
    pass_max: float | None = None,
    warn_max: float | None = None,
    pass_min: float | None = None,
    warn_min: float | None = None,
) -> str:
    """Map a numeric measurement to GREEN / YELLOW / RED."""
    if value is None or not math.isfinite(value):
        return "YELLOW"

    if pass_range is not None:
        lo, hi = pass_range
        if lo <= value <= hi:
            return "GREEN"
        if warn_range is not None:
            wlo, whi = warn_range
            if wlo <= value <= whi:
                return "YELLOW"
        return "RED"

    # Lower-is-better (absolute deviation style).
    if pass_max is not None and warn_max is not None:
        if value <= pass_max:
            return "GREEN"
        if value <= warn_max:
            return "YELLOW"
        return "RED"

    # Higher-is-better.
    if pass_min is not None and warn_min is not None:
        if value >= pass_min:
            return "GREEN"
        if value >= warn_min:
            return "YELLOW"
        return "RED"

    return "YELLOW"


def _shoulder_tilt_deg(frame: dict[str, dict[str, float]]) -> float | None:
    l_sh, r_sh = xy(frame, "left_shoulder"), xy(frame, "right_shoulder")
    if not l_sh or not r_sh:
        return None
    dx = r_sh[0] - l_sh[0]
    dy = r_sh[1] - l_sh[1]
    return abs(math.degrees(math.atan2(dy, abs(dx) + 1e-6)))


def _release_arc_deg(
    shoulder: tuple[float, float],
    wrist: tuple[float, float],
) -> float:
    dx = wrist[0] - shoulder[0]
    dy = -(wrist[1] - shoulder[1])
    return abs(math.degrees(math.atan2(dy, dx + 1e-6)))


def _metric(
    *,
    key: str,
    label: str,
    value: float | None,
    display: str,
    color: str,
    unit: str | None = None,
) -> dict[str, Any]:
    return {
        "key": key,
        "label": label,
        "value": None if value is None else round(float(value), 1),
        "display": display,
        "color": color,
        "unit": unit,
    }


def build_frame_metrics(
    landmarks: Any,
    phases: dict[str, Any],
    fps: float = 30.0,
) -> list[dict[str, Any]]:
    """
    Build a compact per-frame measurement series for fast playback scrubbing.

    Does not include raw landmark coordinates — only coach-facing angles /
    ratios and GREEN/YELLOW/RED status for each primary category.
    """
    frames, timestamps, video_frames = unpack_pose_frames(landmarks, fps)
    if not frames:
        return []

    n = len(frames)
    safe_fps = float(phases.get("fps") or fps or 30.0)
    if len(timestamps) != n:
        timestamps = [i / safe_fps for i in range(n)]
    if len(video_frames) != n:
        video_frames = list(range(n))

    # Confidence from AI phase detector (aligned by sample index).
    phase_conf = [0.0] * n
    raw_fp = phases.get("frame_phases") if isinstance(phases, dict) else None
    if isinstance(raw_fp, list):
        for i, item in enumerate(raw_fp):
            if i < n and isinstance(item, dict):
                phase_conf[i] = float(item.get("confidence") or 0.0)

    series: list[dict[str, Any]] = []
    for i, frame in enumerate(frames):
        phase_key = phase_name_for_index(phases, i)
        phase_label = PHASE_LABELS.get(phase_key, phase_key)
        highlight = list(PHASE_HIGHLIGHTS.get(phase_key, []))

        side = shooting_side(frame)

        # --- Elbow ---
        elbow_angle: float | None = None
        flare: float | None = None
        arm = side_points(frame, side, ("shoulder", "elbow", "wrist"))
        if arm is not None:
            elbow_angle = float(calculate_angle(arm[0], arm[1], arm[2]))
            flare = float(elbow_flare(arm[0], arm[1], arm[2]))

        # --- Knee bend (from standing) ---
        knee_bend: float | None = None
        bends: list[float] = []
        for s in ("left", "right"):
            leg = side_points(frame, s, ("hip", "knee", "ankle"))
            if leg is not None:
                bends.append(
                    bend_from_standing(calculate_angle(leg[0], leg[1], leg[2]))
                )
        if bends:
            knee_bend = float(np.mean(bends))
        else:
            leg = side_points(frame, side, ("hip", "knee", "ankle"))
            if leg is not None:
                knee_bend = bend_from_standing(
                    calculate_angle(leg[0], leg[1], leg[2])
                )

        # --- Shoulder / balance ---
        shoulder_tilt = _shoulder_tilt_deg(frame)
        torso_tilt: float | None = None
        l_hip, r_hip = xy(frame, "left_hip"), xy(frame, "right_hip")
        l_sh, r_sh = xy(frame, "left_shoulder"), xy(frame, "right_shoulder")
        if l_hip and r_hip and l_sh and r_sh:
            mid_hip_x = (l_hip[0] + r_hip[0]) / 2
            mid_sh_x = (l_sh[0] + r_sh[0]) / 2
            torso_tilt = abs(mid_sh_x - mid_hip_x)

        # --- Feet & stance ---
        stance_ratio: float | None = None
        if l_sh and r_sh:
            l_ankle, r_ankle = xy(frame, "left_ankle"), xy(frame, "right_ankle")
            if l_ankle and r_ankle:
                shoulder_w = abs(l_sh[0] - r_sh[0]) or 0.2
                stance_ratio = abs(l_ankle[0] - r_ankle[0]) / shoulder_w

        # --- Release ---
        release_arc: float | None = None
        release_height_delta: float | None = None
        wrist = xy(frame, f"{side}_wrist")
        shoulder = xy(frame, f"{side}_shoulder")
        nose = xy(frame, "nose")
        if wrist and shoulder:
            release_arc = _release_arc_deg(shoulder, wrist)
            ref_y = nose[1] if nose else shoulder[1]
            release_height_delta = wrist[1] - ref_y

        # Category colors / displays
        feet_color = _band_color(
            stance_ratio,
            pass_range=(cfg.STANCE_WIDTH_MIN, cfg.STANCE_WIDTH_MAX),
            warn_range=(
                cfg.STANCE_WIDTH_MIN - 0.15,
                cfg.STANCE_WIDTH_MAX + 0.15,
            ),
        )
        knee_color = _band_color(
            knee_bend,
            pass_range=cfg.KNEE_BEND_PASS,
            warn_range=cfg.KNEE_BEND_WARN,
        )
        balance_color = _band_color(
            shoulder_tilt if shoulder_tilt is not None else torso_tilt,
            pass_max=4.0 if shoulder_tilt is not None else cfg.TORSO_TILT_PASS,
            warn_max=8.0 if shoulder_tilt is not None else cfg.TORSO_TILT_WARN,
        )

        # Elbow: gather/set prefers ~90°, release prefers extension.
        if phase_key in ("release", "follow_through", "landing"):
            elbow_color = _band_color(
                elbow_angle,
                pass_min=cfg.ELBOW_RELEASE_PASS_MIN,
                warn_min=cfg.ELBOW_RELEASE_WARN_MIN,
            )
            if flare is not None and flare > cfg.ELBOW_FLARE_WARN:
                elbow_color = "RED"
            elif flare is not None and flare > cfg.ELBOW_FLARE_PASS and elbow_color == "GREEN":
                elbow_color = "YELLOW"
        else:
            elbow_color = _band_color(
                elbow_angle,
                pass_range=cfg.ELBOW_SET_PASS,
                warn_range=cfg.ELBOW_SET_WARN,
            )
            if flare is not None and flare > cfg.ELBOW_FLARE_WARN:
                elbow_color = "RED"
            elif flare is not None and flare > cfg.ELBOW_FLARE_PASS and elbow_color == "GREEN":
                elbow_color = "YELLOW"

        release_color = _band_color(
            release_height_delta,
            pass_max=cfg.RELEASE_ABOVE_NOSE_PASS,
            warn_max=cfg.RELEASE_ABOVE_NOSE_WARN,
        )
        if release_arc is not None:
            arc_color = _band_color(
                release_arc,
                pass_range=cfg.RELEASE_ARC_PASS,
                warn_range=cfg.RELEASE_ARC_WARN,
            )
            # Prefer worse of height vs arc near release phases.
            if phase_key in ("set_point", "release"):
                order = {"GREEN": 2, "YELLOW": 1, "RED": 0}
                if order.get(arc_color, 1) < order.get(release_color, 1):
                    release_color = arc_color

        follow_color = _band_color(
            elbow_angle,
            pass_min=cfg.FOLLOW_EXTENSION_PASS,
            warn_min=cfg.FOLLOW_EXTENSION_WARN,
        )

        feet_display = (
            f"{stance_ratio:.2f}×" if stance_ratio is not None else "—"
        )
        knee_display = (
            f"{knee_bend:.0f}°" if knee_bend is not None else "—"
        )
        balance_display = (
            f"{shoulder_tilt:.0f}°" if shoulder_tilt is not None else "—"
        )
        elbow_display = (
            f"{elbow_angle:.0f}°" if elbow_angle is not None else "—"
        )
        if release_arc is not None:
            release_display = f"{release_arc:.0f}°"
        elif release_height_delta is not None:
            release_display = (
                "High"
                if release_height_delta <= cfg.RELEASE_ABOVE_NOSE_PASS
                else "Low"
            )
        else:
            release_display = "—"
        follow_display = elbow_display

        # Live panel mirrors the 5 focus-phase rubrics.
        metrics = [
            _metric(
                key="stance",
                label="Stance",
                value=stance_ratio,
                display=f"{feet_display} · {balance_display}",
                color=feet_color if feet_color != "GREEN" else balance_color,
                unit="spacing / tilt",
            ),
            _metric(
                key="load",
                label="Load",
                value=knee_bend,
                display=knee_display,
                color=knee_color,
                unit="° knee",
            ),
            _metric(
                key="set_point",
                label="Set Point",
                value=elbow_angle,
                display=elbow_display,
                color=elbow_color,
                unit="° elbow",
            ),
            _metric(
                key="release",
                label="Release",
                value=elbow_angle if phase_key in ("release", "follow_through") else release_arc,
                display=(
                    elbow_display
                    if phase_key in ("release", "follow_through")
                    else release_display
                ),
                color=(
                    elbow_color
                    if phase_key in ("release", "follow_through")
                    else release_color
                ),
                unit="°",
            ),
            _metric(
                key="follow_through",
                label="Follow Through",
                value=elbow_angle,
                display=follow_display,
                color=follow_color,
                unit="°",
            ),
        ]

        series.append(
            {
                "t": round(float(timestamps[i]), 3),
                "frame": int(video_frames[i]),
                "sample_index": i,
                "phase": phase_key,
                "shot_phase": phase_key,
                "phase_label": phase_label,
                "confidence": round(phase_conf[i], 4),
                "highlight": highlight,
                "metrics": metrics,
                # Convenience angles for the live panel (no raw coords).
                "elbow_angle": None if elbow_angle is None else round(elbow_angle, 1),
                "knee_angle": None if knee_bend is None else round(knee_bend, 1),
                "shoulder_tilt": None
                if shoulder_tilt is None
                else round(shoulder_tilt, 1),
            }
        )

    return series


def enrich_timeline_with_spans(
    phases: dict[str, Any],
    timeline: list[dict[str, Any]],
    landmarks: Any,
    fps: float = 30.0,
) -> list[dict[str, Any]]:
    """Attach start/end seconds so UI can seek to the beginning of a phase."""
    frames, timestamps, _ = unpack_pose_frames(landmarks, fps)
    safe_fps = float(phases.get("fps") or fps or 30.0)
    if len(frames) > 0 and len(timestamps) != len(frames):
        timestamps = np.asarray([i / safe_fps for i in range(len(frames))], dtype=float)

    enriched: list[dict[str, Any]] = []
    for row in timeline:
        key = row.get("phase_key") or ""
        meta = phases.get(key) or {}
        # Prefer span seconds already computed by the phase detector.
        if meta.get("start_seconds") is not None and meta.get("end_seconds") is not None:
            start_seconds = float(meta["start_seconds"])
            end_seconds = float(meta["end_seconds"])
        elif len(timestamps) > 0:
            start_i = int(meta.get("start_frame", meta.get("frame", 0)))
            end_i = int(meta.get("end_frame", meta.get("frame", 0)))
            start_i = max(0, min(start_i, len(timestamps) - 1))
            end_i = max(start_i, min(end_i, len(timestamps) - 1))
            start_seconds = float(timestamps[start_i])
            end_seconds = float(timestamps[end_i])
        else:
            start_seconds = float(meta.get("seconds", row.get("seconds", 0.0)))
            end_seconds = start_seconds

        enriched.append(
            {
                **row,
                # Seek target = beginning of the phase.
                "seconds": round(start_seconds, 3),
                "start_seconds": round(start_seconds, 3),
                "end_seconds": round(end_seconds, 3),
                "key_seconds": round(float(meta.get("seconds", start_seconds)), 3),
                "label": PHASE_LABELS.get(key, row.get("phase", key)),
            }
        )
    return enriched
