"""
Personalized baseline architecture for ShootIQ biomechanics.

Design:
- Every analysis emits numeric baseline_features + measurement confidence.
- After enough history (MIN_SAMPLES), a personal baseline can be computed.
- Ideal basketball thresholds remain the primary scoring source.
- When PERSONALIZED_SCORING_ENABLED is True AND a baseline is supplied,
  consistent personal mechanics can soft-reduce unnecessary penalties.

Displayed score fields stay identical unless PERSONALIZED_SCORING_ENABLED
is turned on (default: False).
"""

from __future__ import annotations

from typing import Any

import numpy as np

from pose_utils import as_frames, shooting_side, xy

# --- Feature flags / gates -------------------------------------------------

# Keep False until product enables personalized displayed scores.
PERSONALIZED_SCORING_ENABLED = False

# Minimum completed analyses before a personal baseline is considered ready.
MIN_BASELINE_SAMPLES = 20

# Soft-adjust clamps (only used when PERSONALIZED_SCORING_ENABLED).
MAX_SCORE_BOOST = 8
MAX_SCORE_PENALTY_RELIEF = 12


def window_confidence(
    frames: list[dict[str, Any]],
    joint_names: list[str],
    *,
    side: str | None = None,
) -> float:
    """
    Average MediaPipe visibility for joints in a phase window.

    joint_names may be bare ('elbow') or fully qualified ('left_elbow').
    """
    if not frames:
        return 0.0

    vis: list[float] = []
    for frame in frames:
        use_side = side or shooting_side(frame)
        for name in joint_names:
            keys = [name] if "_" in name else [f"{use_side}_{name}", name]
            # Also try both sides for bilateral joints.
            if "_" not in name and name in ("ankle", "knee", "hip", "shoulder"):
                keys.extend([f"left_{name}", f"right_{name}"])
            for key in keys:
                point = frame.get(key)
                if isinstance(point, dict) and "visibility" in point:
                    vis.append(float(point["visibility"]))
                    break

    if not vis:
        return 0.45  # unknown visibility — moderate confidence
    return float(np.clip(float(np.mean(vis)), 0.0, 1.0))


def extract_phase_landmarks(
    landmarks: Any,
    phases: dict[str, Any],
) -> dict[str, dict[str, dict[str, float]]]:
    """Compact keyframe landmarks for durable baseline storage."""
    frames = as_frames(landmarks)
    if not frames:
        return {}

    keys = (
        "setup",
        "gather",
        "knee_load",
        "set_point",
        "release",
        "follow_through",
        "landing",
    )
    tracked = (
        "nose",
        "left_shoulder",
        "right_shoulder",
        "left_elbow",
        "right_elbow",
        "left_wrist",
        "right_wrist",
        "left_hip",
        "right_hip",
        "left_knee",
        "right_knee",
        "left_ankle",
        "right_ankle",
    )
    out: dict[str, dict[str, dict[str, float]]] = {}
    for key in keys:
        meta = phases.get(key) or {}
        idx = int(meta.get("frame", 0))
        idx = int(np.clip(idx, 0, len(frames) - 1))
        frame = frames[idx]
        compact: dict[str, dict[str, float]] = {}
        for name in tracked:
            point = xy(frame, name)
            if point is None:
                continue
            raw = frame.get(name) or {}
            compact[name] = {
                "x": round(point[0], 4),
                "y": round(point[1], 4),
                "visibility": round(float(raw.get("visibility", 0.0)), 3),
            }
        out[key] = compact
    return out


def features_from_biomechanics(
    biomechanics: list[dict[str, Any]],
) -> dict[str, float]:
    """Flatten per-category numeric features into one baseline feature map."""
    merged: dict[str, float] = {}
    for item in biomechanics:
        feats = item.get("features")
        if not isinstance(feats, dict):
            continue
        for key, value in feats.items():
            if isinstance(value, (int, float)):
                # Prefer short stable keys (release_height_delta, knee_bend_deg, …).
                merged[str(key)] = float(value)
    return merged


def confidence_map(biomechanics: list[dict[str, Any]]) -> dict[str, float]:
    out: dict[str, float] = {}
    for item in biomechanics:
        conf = item.get("confidence")
        if conf is None:
            continue
        out[str(item.get("category", ""))] = round(float(conf), 3)
    return out


def compute_personal_baseline(
    samples: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """
    Build a personal baseline from historical feature maps.

    Each sample should look like:
      {"features": {...}, "confidence": {...}, "scores": {...}}
    """
    if len(samples) < MIN_BASELINE_SAMPLES:
        return None

    feature_series: dict[str, list[float]] = {}
    score_series: dict[str, list[float]] = {}
    weights: dict[str, list[float]] = {}

    for sample in samples:
        feats = sample.get("features") or {}
        scores = sample.get("scores") or {}
        conf = sample.get("confidence") or {}
        avg_conf = float(np.mean(list(conf.values()))) if conf else 0.7
        for key, value in feats.items():
            if not isinstance(value, (int, float)):
                continue
            feature_series.setdefault(key, []).append(float(value))
            weights.setdefault(key, []).append(avg_conf)
        for key, value in scores.items():
            if isinstance(value, (int, float)):
                score_series.setdefault(key, []).append(float(value))

    def _stats(values: list[float], w: list[float] | None = None) -> dict[str, float]:
        arr = np.asarray(values, dtype=float)
        if w and len(w) == len(values):
            ww = np.asarray(w, dtype=float)
            mean = float(np.average(arr, weights=ww))
        else:
            mean = float(np.mean(arr))
        return {
            "mean": round(mean, 4),
            "median": round(float(np.median(arr)), 4),
            "std": round(float(np.std(arr)), 4),
            "p25": round(float(np.percentile(arr, 25)), 4),
            "p75": round(float(np.percentile(arr, 75)), 4),
            "n": float(len(values)),
        }

    features = {
        key: _stats(vals, weights.get(key))
        for key, vals in feature_series.items()
        if len(vals) >= max(5, MIN_BASELINE_SAMPLES // 4)
    }
    scores = {
        key: _stats(vals)
        for key, vals in score_series.items()
        if len(vals) >= max(5, MIN_BASELINE_SAMPLES // 4)
    }

    # Consistency index: lower average CV → higher consistency (0–1).
    cvs: list[float] = []
    for stats in features.values():
        mean = abs(stats["mean"]) if abs(stats["mean"]) > 1e-6 else 1.0
        cvs.append(min(1.5, stats["std"] / mean))
    consistency = float(np.clip(1.0 - float(np.mean(cvs) if cvs else 1.0), 0.0, 1.0))

    return {
        "version": 1,
        "sample_count": len(samples),
        "min_samples": MIN_BASELINE_SAMPLES,
        "ready": True,
        "consistency": round(consistency, 3),
        "features": features,
        "scores": scores,
    }


def _relief_for_feature(
    value: float,
    personal: dict[str, float],
    ideal_center: float,
    ideal_tolerance: float,
    consistency: float,
) -> float:
    """
    Return a positive score relief when the shot matches a tight personal
    baseline that sits slightly off the ideal center.
    """
    p_mean = personal.get("mean")
    p_std = personal.get("std")
    if p_mean is None or p_std is None:
        return 0.0

    # Must be consistent personally.
    if p_std > ideal_tolerance * 0.85:
        return 0.0
    if consistency < 0.55:
        return 0.0

    # Personal mean is near-ideal but not exact — soft zone.
    personal_offset = abs(p_mean - ideal_center)
    if personal_offset < ideal_tolerance * 0.35:
        return 0.0  # already ideal — no relief needed
    if personal_offset > ideal_tolerance * 2.2:
        return 0.0  # too far from accepted biomechanics

    # Current shot must match the personal pattern.
    if abs(value - p_mean) > max(p_std * 1.5, ideal_tolerance * 0.4):
        return 0.0

    proximity = 1.0 - min(1.0, abs(value - p_mean) / (p_std + 1e-6) / 2.0)
    offset_factor = 1.0 - min(1.0, (personal_offset - ideal_tolerance * 0.35) / (
        ideal_tolerance * 1.85
    ))
    relief = MAX_SCORE_PENALTY_RELIEF * proximity * offset_factor * consistency
    return float(np.clip(relief, 0.0, MAX_SCORE_PENALTY_RELIEF))


def apply_personalization(
    biomechanics: list[dict[str, Any]],
    baseline: dict[str, Any] | None,
    *,
    enabled: bool | None = None,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """
    Optionally soft-adjust category scores using personal baseline.

    Returns (possibly adjusted biomechanics, personalization metadata).
    When disabled, biomechanics scores are unchanged.
    """
    use = PERSONALIZED_SCORING_ENABLED if enabled is None else enabled
    meta: dict[str, Any] = {
        "enabled": bool(use),
        "min_samples": MIN_BASELINE_SAMPLES,
        "applied": False,
        "baseline_ready": bool(baseline and baseline.get("ready")),
        "sample_count": int((baseline or {}).get("sample_count") or 0),
        "consistency": (baseline or {}).get("consistency"),
        "adjustments": {},
    }

    if not use or not baseline or not baseline.get("ready"):
        meta["note"] = (
            "Ideal biomechanics scoring active. "
            "Personal baseline is recorded but not applied to displayed scores."
        )
        return biomechanics, meta

    consistency = float(baseline.get("consistency") or 0.0)
    feature_stats = baseline.get("features") or {}
    adjusted: list[dict[str, Any]] = []
    adjustments: dict[str, Any] = {}

    for item in biomechanics:
        clone = dict(item)
        feats = item.get("features") or {}
        category = str(item.get("category", ""))
        score = int(item.get("score", 0))
        relief = 0.0

        # Release Point: classic case — consistent personal release height/angle.
        if "Release" in category:
            height = feats.get("release_height_delta")
            if height is not None and "release_height_delta" in feature_stats:
                relief = max(
                    relief,
                    _relief_for_feature(
                        float(height),
                        feature_stats["release_height_delta"],
                        ideal_center=-0.02,
                        ideal_tolerance=0.04,
                        consistency=consistency,
                    ),
                )
            arc = feats.get("release_arc_deg")
            if arc is not None and "release_arc_deg" in feature_stats:
                relief = max(
                    relief,
                    _relief_for_feature(
                        float(arc),
                        feature_stats["release_arc_deg"],
                        ideal_center=52.5,
                        ideal_tolerance=10.0,
                        consistency=consistency,
                    ),
                )

        if "Elbow" in category:
            flare = feats.get("elbow_flare")
            if flare is not None and "elbow_flare" in feature_stats:
                relief = max(
                    relief,
                    _relief_for_feature(
                        float(flare),
                        feature_stats["elbow_flare"],
                        ideal_center=0.02,
                        ideal_tolerance=0.035,
                        consistency=consistency,
                    )
                    * 0.75,
                )

        if "Knee" in category:
            bend = feats.get("knee_bend_deg")
            if bend is not None and "knee_bend_deg" in feature_stats:
                relief = max(
                    relief,
                    _relief_for_feature(
                        float(bend),
                        feature_stats["knee_bend_deg"],
                        ideal_center=60.0,
                        ideal_tolerance=15.0,
                        consistency=consistency,
                    )
                    * 0.7,
                )

        # Weight relief by measurement confidence.
        conf = float(item.get("confidence") or 0.7)
        relief *= conf

        if relief >= 0.5 and score < 95:
            new_score = int(np.clip(round(score + relief), 0, 100))
            # Never boost past a soft ceiling from a weak raw score.
            new_score = min(new_score, max(score, min(94, score + MAX_SCORE_BOOST)))
            if new_score != score:
                from biomechanics_config import color_for_status, status_from_score

                clone["score"] = new_score
                clone["status"] = status_from_score(new_score)
                clone["color"] = color_for_status(clone["status"])
                clone["personalization_delta"] = new_score - score
                adjustments[category] = {
                    "from": score,
                    "to": new_score,
                    "relief": round(relief, 2),
                }

        # Always keep ideal score visible for audit / future UI.
        clone["ideal_score"] = score
        adjusted.append(clone)

    meta["applied"] = bool(adjustments)
    meta["adjustments"] = adjustments
    meta["note"] = (
        "Personalized consistency relief applied."
        if adjustments
        else "Baseline ready; no relief needed for this shot."
    )
    return adjusted, meta


def build_analysis_personalization_payload(
    biomechanics: list[dict[str, Any]],
    phases: dict[str, Any],
    landmarks: Any,
    baseline: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Bundle features/landmarks/confidence for persistence + future scoring."""
    features = features_from_biomechanics(biomechanics)
    return {
        "baseline_features": features,
        "measurement_confidence": confidence_map(biomechanics),
        "phase_landmarks": extract_phase_landmarks(landmarks, phases),
        "personalization": {
            "enabled": PERSONALIZED_SCORING_ENABLED,
            "min_samples": MIN_BASELINE_SAMPLES,
            "baseline_ready": bool(baseline and baseline.get("ready")),
            "sample_count": int((baseline or {}).get("sample_count") or 0),
        },
    }
