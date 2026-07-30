"""AI Shot Phase Detection — temporal classification before biomechanics.

Public API
----------
detect_phases(landmarks, fps=30, sample_every=1, ...)
    → phases dict (analyzer-compatible) + per-frame labels

Architecture
------------
features.extract_temporal_features  — motion series from landmarks
classifier.PhaseClassifier          — swappable interface
temporal_viterbi.TemporalMotionClassifier — production motion HMM (no static-angle gates)
dataset.LabeledShotExample          — schema for future elite-shooter training

Machine keys stay setup/knee_load for analyzer compatibility.
Display labels: Stance / Gather / Load / Upward Motion / Release / Follow Through / Landing.
"""

from __future__ import annotations

from shot_phase_detection.classifier import PhaseClassifier, get_default_classifier
from shot_phase_detection.schema import (
    PHASE_ALIASES,
    PHASE_COLORS,
    PHASE_LABELS,
    PHASE_ORDER,
    FramePhaseLabel,
)
from shot_phase_detection.service import detect_phases, phases_from_frame_labels

__all__ = [
    "PHASE_ORDER",
    "PHASE_LABELS",
    "PHASE_COLORS",
    "PHASE_ALIASES",
    "FramePhaseLabel",
    "PhaseClassifier",
    "get_default_classifier",
    "detect_phases",
    "phases_from_frame_labels",
]
