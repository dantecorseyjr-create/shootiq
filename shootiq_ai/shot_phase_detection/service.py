"""Orchestrate feature extraction → classifier → analyzer-compatible phases."""

from __future__ import annotations

from typing import Any

from shot_phase_detection.classifier import PhaseClassifier, get_default_classifier
from shot_phase_detection.features import extract_temporal_features
from shot_phase_detection.schema import (
    PHASE_COLORS,
    PHASE_LABELS,
    PHASE_ORDER,
    FramePhaseLabel,
    format_timestamp,
    normalize_phase_key,
)


def _empty_phases(fps: float) -> dict[str, Any]:
    empty = {
        "frame": 0,
        "seconds": 0.0,
        "timestamp": "00:00",
        "start_frame": 0,
        "end_frame": 0,
        "video_frame": 0,
        "confidence": 0.0,
        "start_seconds": 0.0,
        "end_seconds": 0.0,
    }
    result = {
        key: {**empty, "label": PHASE_LABELS[key], "color": PHASE_COLORS[key]}
        for key in PHASE_ORDER
    }
    result.update(
        {
            "fps": fps,
            "frame_count": 0,
            "order": list(PHASE_ORDER),
            "labels": dict(PHASE_LABELS),
            "colors": dict(PHASE_COLORS),
            "frame_phases": [],
            "detector": {"name": "none", "version": "0"},
            "load": result["knee_load"],
            "stance": result["setup"],
        }
    )
    return result


def phases_from_frame_labels(
    labels: list[FramePhaseLabel],
    *,
    fps: float = 30.0,
    detector: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Collapse per-frame labels into phase spans + keyframes for analyzers."""
    if not labels:
        return _empty_phases(fps)

    n = len(labels)
    by_phase: dict[str, list[int]] = {key: [] for key in PHASE_ORDER}
    for i, lab in enumerate(labels):
        by_phase[normalize_phase_key(lab.shot_phase)].append(i)

    result: dict[str, Any] = {}
    last_end = -1
    for key in PHASE_ORDER:
        idxs = by_phase[key]
        if idxs:
            start_i, end_i = idxs[0], idxs[-1]
        else:
            # Missing phase: degenerate span after previous phase.
            start_i = min(n - 1, max(0, last_end + 1))
            end_i = start_i

        start_i = int(max(0, min(start_i, n - 1)))
        end_i = int(max(start_i, min(end_i, n - 1)))
        last_end = end_i

        run = idxs or [start_i]
        frame_idx = max(run, key=lambda i: labels[i].confidence)
        lab = labels[frame_idx]
        conf = float(sum(labels[i].confidence for i in run) / len(run))

        result[key] = {
            "frame": frame_idx,
            "start_frame": start_i,
            "end_frame": end_i,
            "seconds": round(float(lab.timestamp), 3),
            "timestamp": format_timestamp(float(lab.timestamp)),
            "video_frame": int(lab.frame_number),
            "label": PHASE_LABELS[key],
            "color": PHASE_COLORS[key],
            "confidence": round(conf, 4),
            "start_seconds": round(float(labels[start_i].timestamp), 3),
            "end_seconds": round(float(labels[end_i].timestamp), 3),
        }

    result.update(
        {
            "fps": fps,
            "frame_count": n,
            "order": list(PHASE_ORDER),
            "labels": dict(PHASE_LABELS),
            "colors": dict(PHASE_COLORS),
            "frame_phases": [lab.to_json() for lab in labels],
            "detector": detector
            or {"name": "temporal_motion_viterbi", "version": "1.0.0"},
            "load": result["knee_load"],
            "stance": result["setup"],
            # Back-compat for older analyzers / overlays
            "upward_motion": result["set_point"],
        }
    )
    return result


def detect_phases(
    landmarks: Any,
    fps: float = 30.0,
    *,
    sample_every: int = 1,
    classifier: PhaseClassifier | None = None,
) -> dict[str, Any]:
    """
    Run AI shot-phase detection.

    Returns analyzer-compatible phases dict including:
      - per-phase spans / keyframes
      - frame_phases: [{frame_number, timestamp, shot_phase, confidence}, ...]
      - detector metadata
    """
    safe_fps = fps if fps and fps > 1 else 30.0
    features = extract_temporal_features(
        landmarks,
        fps=safe_fps,
        sample_every=max(1, int(sample_every)),
    )
    if features is None or features.n == 0:
        return _empty_phases(safe_fps)

    clf = classifier or get_default_classifier()
    labels = clf.predict(
        features,
        meta={"fps": safe_fps, "sample_every": sample_every},
    )
    return phases_from_frame_labels(
        labels,
        fps=safe_fps,
        detector=clf.describe(),
    )
