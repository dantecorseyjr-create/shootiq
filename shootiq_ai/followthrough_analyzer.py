"""Follow Through — arm extension, wrist flexion, balance, hold duration."""

from __future__ import annotations

from typing import Any

import numpy as np

import biomechanics_config as cfg
from personalization import window_confidence
from pose_eval import body_balance, elbow_angle, wrist_flexion_proxy
from pose_utils import as_frames, make_category, resolve_phases


def analyze_follow_through(
    landmarks: Any,
    fps: float = 30.0,
    phases: dict[str, Any] | None = None,
    timestamp: float | None = None,
) -> dict[str, Any]:
    """Follow Through phase only."""
    frames = as_frames(landmarks)
    phases = resolve_phases(landmarks, fps, phases)
    seek = phases["follow_through"]

    release_i = int(phases["release"]["frame"])
    start = max(
        release_i + 1,
        int(phases["follow_through"].get("start_frame", release_i + 1)),
    )
    end = int(phases["follow_through"].get("end_frame", start))
    end = min(len(frames) - 1, max(start, end))
    window = frames[start : end + 1]
    if not window:
        window = frames[release_i + 1 : min(len(frames), release_i + 4)]

    # Prefer real timestamps from phase spans when available.
    start_t = float(
        phases["follow_through"].get(
            "start_seconds",
            phases["follow_through"].get("seconds", start / max(fps, 1)),
        )
    )
    end_t = float(
        phases["follow_through"].get(
            "end_seconds",
            phases["follow_through"].get("seconds", end / max(fps, 1)),
        )
    )
    span_duration = max(0.0, end_t - start_t)

    extensions: list[float] = []
    flexions: list[float] = []
    balances: list[float] = []
    hold_samples = 0
    for frame in window:
        ext = elbow_angle(frame)
        flex = wrist_flexion_proxy(frame)
        bal = body_balance(frame)
        if ext is not None:
            extensions.append(ext)
            if ext >= cfg.FOLLOW_EXTENSION_WARN:
                hold_samples += 1
        if flex is not None:
            flexions.append(flex)
        if bal is not None:
            balances.append(bal["balance_score"])

    # Hold duration ≈ fraction of follow span still extended.
    hold_ratio = hold_samples / max(len(window), 1)
    hold_seconds = hold_ratio * span_duration if span_duration > 0 else (
        hold_samples / max(fps, 1.0)
    )

    stamp = seek["timestamp"]
    secs = float(seek["seconds"] if timestamp is None else timestamp)
    highlight = ["elbow", "wrist", "shoulder", "hip", "torso"]
    conf = window_confidence(window, ["elbow", "wrist", "shoulder", "hip"])

    if not extensions:
        return make_category(
            category="Follow Through",
            score=0,
            measurement="Follow-through not detected",
            issue="Could not measure follow-through after release",
            correction="Hold your finish until the ball reaches the rim",
            timestamp=stamp,
            seconds=secs,
            highlight=highlight,
            phase="Follow Through",
            phase_key="follow_through",
            playback_speed=0.5,
            auto_play=True,
            confidence=min(conf, 0.25),
        )

    max_ext = float(np.max(extensions))
    mean_ext = float(np.mean(extensions))
    wrist_flex = float(np.max(flexions)) if flexions else 0.0
    balance = float(np.mean(balances)) if balances else 0.0

    score = 92
    issues: list[str] = []
    corrections: list[str] = []

    if max_ext < cfg.FOLLOW_EXTENSION_WARN:
        score -= 26
        issues.append("Arm extension collapses on the follow-through")
        corrections.append("Fully extend and freeze the shooting arm after release")
    elif mean_ext < cfg.FOLLOW_EXTENSION_PASS:
        score -= 12
        issues.append("Arm extension shortens on the finish")

    if wrist_flex < cfg.FOLLOW_WRIST_FLEX_WARN:
        score -= 18
        issues.append("Wrist flexion / goose-neck is missing")
        corrections.append("Relax the wrist downward and hold the goose-neck")
    elif wrist_flex < cfg.FOLLOW_WRIST_FLEX_PASS:
        score -= 8
        issues.append("Hold a deeper wrist flexion on the finish")

    if balance > cfg.FOLLOW_BALANCE_WARN:
        score -= 14
        issues.append("Body balance breaks during follow-through")
        corrections.append("Stay stacked over your base through the finish")
    elif balance > cfg.FOLLOW_BALANCE_PASS:
        score -= 6
        issues.append("Slight balance drift on the follow-through")

    if hold_seconds < cfg.FOLLOW_HOLD_WARN_S:
        score -= 20
        issues.append(
            f"Follow-through held only {hold_seconds:.2f}s — ends too early"
        )
        corrections.append("Hold the finish longer after the ball leaves your hand")
    elif hold_seconds < cfg.FOLLOW_HOLD_PASS_S:
        score -= 10
        issues.append(f"Follow-through hold is short ({hold_seconds:.2f}s)")

    score = int(np.clip(score, 30, 100))
    if not issues:
        issue = "Excellent follow-through — extension, wrist, balance, and hold"
        correction = "Keep freezing that finish on every shot"
    else:
        issue = issues[0]
        correction = corrections[0] if corrections else (
            "Extend, flex the wrist, stay balanced, and hold the finish"
        )

    return make_category(
        category="Follow Through",
        score=score,
        measurement=(
            f"Extension {max_ext:.0f}°, wrist flex {wrist_flex:.3f}, "
            f"balance {balance:.3f}, hold {hold_seconds:.2f}s"
        ),
        issue=issue,
        correction=correction,
        timestamp=stamp,
        seconds=secs,
        highlight=highlight,
        phase="Follow Through",
        phase_key="follow_through",
        playback_speed=0.5,
        auto_play=True,
        confidence=conf,
        features={
            "follow_extension_deg": max_ext,
            "follow_wrist_flex": wrist_flex,
            "follow_balance": balance,
            "follow_hold_seconds": hold_seconds,
            "follow_hold_ratio": hold_ratio,
        },
    )
