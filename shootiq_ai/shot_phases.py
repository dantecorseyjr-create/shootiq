"""Shot-phase helpers (compatibility layer).

Phase *detection* lives in `shot_phase_detection` (temporal motion classifier).
This module re-exports schema + windowing helpers used by analyzers.
"""

from __future__ import annotations

from typing import Any

from shot_phase_detection import (
    PHASE_COLORS,
    PHASE_LABELS,
    PHASE_ORDER,
    detect_phases,
)
from shot_phase_detection.schema import format_timestamp, normalize_phase_key

# Re-export for existing imports.
__all__ = [
    "PHASE_ORDER",
    "PHASE_LABELS",
    "PHASE_COLORS",
    "format_timestamp",
    "detect_shot_phases",
    "phase_window",
    "frames_between",
    "phase_name_for_index",
    "timeline_entries",
]


def detect_shot_phases(
    landmarks: Any,
    fps: float = 30.0,
    *,
    sample_every: int = 1,
) -> dict[str, Any]:
    """
    AI shot-phase detection (temporal motion classifier).

    Prefer passing sample_every from pose_data when available so metadata
    is accurate; velocities use frame timestamps.
    """
    # Infer sample_every from pose_data payload when present.
    every = sample_every
    if isinstance(landmarks, dict) and landmarks.get("sample_every"):
        every = int(landmarks["sample_every"])
    return detect_phases(landmarks, fps=fps, sample_every=every)


def phase_window(
    frames: list[Any],
    phases: dict[str, Any],
    phase_key: str,
    *,
    pad: int = 0,
) -> list[Any]:
    """Slice frames for a single phase (inclusive), with optional padding."""
    key = normalize_phase_key(phase_key)
    if not frames or key not in phases:
        return frames
    meta = phases[key]
    start = max(0, int(meta.get("start_frame", meta.get("frame", 0))) - pad)
    end = min(
        len(frames),
        int(meta.get("end_frame", meta.get("frame", 0))) + 1 + pad,
    )
    window = frames[start:end]
    return window or frames[start : start + 1]


def frames_between(
    frames: list[Any],
    phases: dict[str, Any],
    start_key: str,
    end_key: str,
    *,
    pad: int = 0,
) -> list[Any]:
    """Slice frames from the start of start_key through the end of end_key."""
    if not frames:
        return frames
    start_key = normalize_phase_key(start_key)
    end_key = normalize_phase_key(end_key)
    start = int(phases.get(start_key, {}).get("start_frame", 0)) - pad
    end = int(phases.get(end_key, {}).get("end_frame", len(frames) - 1)) + 1 + pad
    start = max(0, start)
    end = min(len(frames), max(start + 1, end))
    return frames[start:end]


def phase_name_for_index(phases: dict[str, Any], frame_index: int) -> str:
    """Return the phase key containing a sampled-frame index."""
    # Prefer authoritative per-frame labels when present.
    frame_phases = phases.get("frame_phases")
    if isinstance(frame_phases, list) and 0 <= frame_index < len(frame_phases):
        item = frame_phases[frame_index]
        if isinstance(item, dict):
            return normalize_phase_key(item.get("shot_phase") or item.get("phase"))

    for key in PHASE_ORDER:
        meta = phases.get(key) or {}
        start = int(meta.get("start_frame", meta.get("frame", 0)))
        end = int(meta.get("end_frame", meta.get("frame", 0)))
        if start <= frame_index <= end:
            return key

    best = "setup"
    best_dist = 10**9
    for key in PHASE_ORDER:
        frame = int((phases.get(key) or {}).get("frame", 0))
        dist = abs(frame - frame_index)
        if dist < best_dist:
            best_dist = dist
            best = key
    return best


def timeline_entries(
    phases: dict[str, Any],
    statuses: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    """Build UI timeline rows for every detected phase."""
    statuses = statuses or {}
    rows: list[dict[str, Any]] = []
    for key in PHASE_ORDER:
        meta = phases.get(key)
        if not isinstance(meta, dict):
            continue
        start_seconds = meta.get("start_seconds", meta.get("seconds", 0.0))
        rows.append(
            {
                "phase": PHASE_LABELS.get(key, key),
                "phase_key": key,
                "timestamp": meta.get("timestamp", "00:00"),
                "status": statuses.get(key, "PASS"),
                "seconds": start_seconds,
                "start_seconds": start_seconds,
                "end_seconds": meta.get("end_seconds", meta.get("seconds", 0.0)),
                "key_seconds": meta.get("seconds", 0.0),
                "color": meta.get("color") or PHASE_COLORS.get(key, "#94A3B8"),
                "confidence": meta.get("confidence"),
                "label": PHASE_LABELS.get(key, key),
            }
        )
    return rows
