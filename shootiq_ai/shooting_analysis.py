"""
Backward-compatible entrypoint for shooting mechanics.

New modular biomechanics live in:
  feet_analyzer.py, knee_analyzer.py, elbow_analyzer.py,
  wrist_analyzer.py, balance_analyzer.py, release_analyzer.py,
  biomechanics_engine.py
"""

from __future__ import annotations

from typing import Any

from biomechanics_engine import (  # noqa: F401
    analyze_biomechanics,
    analyze_shot_mechanics,
    evaluate_frame_joint_status,
)
from pose_utils import calculate_angle  # noqa: F401 — public helper


def analyze_elbow_alignment(landmarks: Any) -> int:
    from elbow_analyzer import analyze_elbow

    return int(analyze_elbow(landmarks)["score"])


def analyze_knee_bend(landmarks: Any) -> int:
    from knee_analyzer import analyze_knees

    return int(analyze_knees(landmarks)["score"])


def analyze_balance(landmarks: Any) -> int:
    from balance_analyzer import analyze_balance as _balance

    return int(_balance(landmarks)["score"])


def analyze_follow_through(landmarks: Any) -> int:
    from followthrough_analyzer import analyze_follow_through as _follow

    return int(_follow(landmarks)["score"])
