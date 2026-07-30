"""Stance biomechanics — foot spacing, foot stagger, body balance."""

from __future__ import annotations

from typing import Any

import numpy as np

import biomechanics_config as cfg
from personalization import window_confidence
from pose_eval import body_balance, foot_spacing_ratio, foot_stagger
from pose_utils import as_frames, make_category, resolve_phases
from shot_phases import phase_window


def analyze_feet(
    landmarks: Any,
    fps: float = 30.0,
    phases: dict[str, Any] | None = None,
    timestamp: float | None = None,
) -> dict[str, Any]:
    """Stance phase only: spacing + stagger + balance."""
    frames = as_frames(landmarks)
    phases = resolve_phases(landmarks, fps, phases)
    window = phase_window(frames, phases, "setup", pad=1)
    seek = phases["setup"]

    widths: list[float] = []
    staggers: list[float] = []
    balances: list[float] = []
    for frame in window:
        w = foot_spacing_ratio(frame)
        s = foot_stagger(frame)
        bal = body_balance(frame)
        if w is not None:
            widths.append(w)
        if s is not None:
            staggers.append(s)
        if bal is not None:
            balances.append(bal["balance_score"])

    stamp = seek["timestamp"]
    secs = float(seek["seconds"] if timestamp is None else timestamp)
    highlight = ["ankle", "foot", "hip", "torso"]
    conf = window_confidence(window, ["ankle", "hip", "shoulder"])

    if not widths:
        return make_category(
            category="Stance",
            score=0,
            measurement="Stance not detected",
            issue="Could not see both feet during stance",
            correction="Stand fully in frame with feet visible before the shot",
            timestamp=stamp,
            seconds=secs,
            highlight=highlight,
            phase="Stance",
            phase_key="setup",
            playback_speed=1.0,
            auto_play=False,
            confidence=min(conf, 0.25),
        )

    width_ratio = float(np.mean(widths))
    stagger = float(np.mean(staggers)) if staggers else 0.0
    balance = float(np.mean(balances)) if balances else 0.0

    score = 92
    issues: list[str] = []
    corrections: list[str] = []

    if width_ratio < cfg.STANCE_WIDTH_MIN:
        score -= 26
        issues.append("Foot spacing is too narrow")
        corrections.append("Set feet about shoulder-width apart")
    elif width_ratio > cfg.STANCE_WIDTH_MAX:
        score -= 16
        issues.append("Foot spacing is too wide")
        corrections.append("Bring your stance closer to shoulder width")

    if stagger < cfg.STANCE_STAGGER_MIN:
        score -= 12
        issues.append("Foot stagger is missing — shooting foot should lead slightly")
        corrections.append("Place your shooting foot slightly ahead")
    elif stagger > cfg.STANCE_STAGGER_MAX:
        score -= 8
        issues.append("Foot stagger is exaggerated")

    if balance > cfg.STANCE_BALANCE_WARN:
        score -= 18
        issues.append("Body balance is off during stance")
        corrections.append("Stack shoulders over hips and feet before you gather")
    elif balance > cfg.STANCE_BALANCE_PASS:
        score -= 8
        issues.append("Slight balance lean at stance")

    score = int(np.clip(score, 35, 100))
    if not issues:
        issue = "Solid foot spacing, stagger, and balance at stance"
        correction = "Keep this base every catch-and-shoot"
    else:
        issue = issues[0]
        correction = corrections[0] if corrections else (
            "Set a balanced, shoulder-width stance with shooting foot slightly ahead"
        )

    return make_category(
        category="Stance",
        score=score,
        measurement=(
            f"Spacing {width_ratio:.2f}× shoulders, "
            f"stagger {stagger:.3f}, balance {balance:.3f}"
        ),
        issue=issue,
        correction=correction,
        timestamp=stamp,
        seconds=secs,
        highlight=highlight,
        phase="Stance",
        phase_key="setup",
        playback_speed=1.0,
        auto_play=False,
        confidence=conf,
        features={
            "stance_width_ratio": width_ratio,
            "stance_stagger": stagger,
            "stance_balance": balance,
        },
    )


# Alias used by older imports / engine naming.
analyze_stance = analyze_feet
