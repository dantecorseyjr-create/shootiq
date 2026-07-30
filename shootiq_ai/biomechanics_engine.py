"""Orchestrate phase-aware MediaPipe biomechanics analyzers."""

from __future__ import annotations

from typing import Any

import numpy as np

import biomechanics_config as cfg
from balance_analyzer import analyze_balance
from elbow_analyzer import analyze_elbow
from feet_analyzer import analyze_feet
from followthrough_analyzer import analyze_follow_through
from knee_analyzer import analyze_knees
from wrist_analyzer import analyze_hand_position
from pose_utils import (
    as_frames,
    bend_from_standing,
    calculate_angle,
    elbow_flare,
    resolve_clip_shooting_side,
    set_clip_shooting_side,
    shooting_side,
    side_points,
    xy,
)
from personalization import (
    PERSONALIZED_SCORING_ENABLED,
    apply_personalization,
    build_analysis_personalization_payload,
)
from release_analyzer import analyze_release
from frame_metrics import build_frame_metrics, enrich_timeline_with_spans
from shot_phases import (
    detect_shot_phases,
    phase_name_for_index,
    timeline_entries,
)


def evaluate_frame_joint_status(
    frame: dict[str, dict[str, float]],
    phase: str | None = None,
) -> dict[str, str]:
    """
    Per-frame GREEN/YELLOW/RED segment status for skeleton overlay.

    When [phase] is provided, only joints relevant to that phase are marked
    WARN/FAIL — others stay PASS so highlights match coaching focus.
    """
    status: dict[str, str] = {
        "ankle": "PASS",
        "knee": "PASS",
        "hip": "PASS",
        "elbow": "PASS",
        "wrist": "PASS",
        "shoulder": "PASS",
        "torso": "PASS",
    }
    side = shooting_side(frame)
    from shot_phase_detection.schema import normalize_phase_key

    phase_key = normalize_phase_key(phase) if phase else ""

    def _active(*keys: str) -> bool:
        if not phase_key:
            return True
        return phase_key in keys

    # Stance — feet + balance
    if _active("setup", "landing", ""):
        l_ankle, r_ankle = xy(frame, "left_ankle"), xy(frame, "right_ankle")
        l_sh, r_sh = xy(frame, "left_shoulder"), xy(frame, "right_shoulder")
        if l_ankle and r_ankle and l_sh and r_sh:
            ratio = abs(l_ankle[0] - r_ankle[0]) / (abs(l_sh[0] - r_sh[0]) or 0.2)
            if ratio < cfg.STANCE_WIDTH_MIN or ratio > cfg.STANCE_WIDTH_MAX:
                status["ankle"] = "FAIL"
            elif abs(ratio - 1.0) > 0.25:
                status["ankle"] = "WARN"

    # Load — knees / hips
    if _active("gather", "knee_load", ""):
        leg = side_points(frame, side, ("hip", "knee", "ankle"))
        if leg is not None:
            bend = bend_from_standing(calculate_angle(leg[0], leg[1], leg[2]))
            lo, hi = cfg.KNEE_BEND_PASS
            wlo, whi = cfg.KNEE_BEND_WARN
            if lo <= bend <= hi:
                status["knee"] = "PASS"
            elif wlo <= bend <= whi:
                status["knee"] = "WARN"
            else:
                status["knee"] = "FAIL"
            status["hip"] = status["knee"]

    # Set Point — elbow / forearm / wrist
    if _active("set_point", ""):
        arm = side_points(frame, side, ("shoulder", "elbow", "wrist"))
        if arm is not None:
            angle = calculate_angle(arm[0], arm[1], arm[2])
            flare = elbow_flare(arm[0], arm[1], arm[2])
            if flare > cfg.ELBOW_FLARE_WARN or not (
                cfg.ELBOW_SET_WARN[0] <= angle <= cfg.ELBOW_SET_WARN[1]
            ):
                status["elbow"] = "FAIL"
            elif flare > cfg.ELBOW_FLARE_PASS or not (
                cfg.ELBOW_SET_PASS[0] <= angle <= cfg.ELBOW_SET_PASS[1]
            ):
                status["elbow"] = "WARN"
            status["wrist"] = status["elbow"]
            status["shoulder"] = "PASS" if flare <= cfg.ELBOW_FLARE_WARN else "WARN"

    # Release — extension + alignment
    if _active("release", ""):
        arm = side_points(frame, side, ("shoulder", "elbow", "wrist"))
        if arm is not None:
            angle = calculate_angle(arm[0], arm[1], arm[2])
            if angle < cfg.ELBOW_RELEASE_WARN_MIN:
                status["elbow"] = "FAIL"
            elif angle < cfg.ELBOW_RELEASE_PASS_MIN:
                status["elbow"] = "WARN"
            else:
                status["elbow"] = "PASS"
            status["wrist"] = status["elbow"]
        l_hip, r_hip = xy(frame, "left_hip"), xy(frame, "right_hip")
        l_sh, r_sh = xy(frame, "left_shoulder"), xy(frame, "right_shoulder")
        if l_hip and r_hip and l_sh and r_sh:
            tilt = abs(((l_sh[0] + r_sh[0]) / 2) - ((l_hip[0] + r_hip[0]) / 2))
            if tilt > cfg.TORSO_TILT_WARN:
                status["torso"] = "FAIL"
            elif tilt > cfg.TORSO_TILT_PASS:
                status["torso"] = "WARN"

    # Follow through — arm/wrist + balance
    if _active("follow_through", ""):
        arm = side_points(frame, side, ("shoulder", "elbow", "wrist"))
        if arm is not None:
            angle = calculate_angle(arm[0], arm[1], arm[2])
            if angle < cfg.FOLLOW_EXTENSION_WARN:
                status["elbow"] = "FAIL"
                status["wrist"] = "FAIL"
            elif angle < cfg.FOLLOW_EXTENSION_PASS:
                status["elbow"] = "WARN"
                status["wrist"] = "WARN"
            else:
                status["elbow"] = "PASS"
                status["wrist"] = "PASS"
            status["shoulder"] = status["elbow"]

    return status


def evaluate_frame_joint_status_for_index(
    frame: dict[str, dict[str, float]],
    phases: dict[str, Any],
    frame_index: int,
) -> dict[str, str]:
    """Phase-aware overlay status for a sampled pose index."""
    return evaluate_frame_joint_status(
        frame,
        phase=phase_name_for_index(phases, frame_index),
    )


def _average_overall(biomechanics: list[dict[str, Any]]) -> int:
    """Weighted overall using CATEGORY_WEIGHTS (falls back to primary mean)."""
    weighted_sum = 0.0
    weight_total = 0.0
    for item in biomechanics:
        cat = str(item.get("category", ""))
        score = int(item.get("score", 0) or 0)
        if score <= 0:
            continue
        weight = float(cfg.CATEGORY_WEIGHTS.get(cat, 0.0))
        if weight <= 0 and cat in cfg.PRIMARY_CATEGORIES:
            weight = 0.20
        if weight <= 0:
            continue
        weighted_sum += score * weight
        weight_total += weight

    if weight_total > 0:
        return int(np.clip(round(weighted_sum / weight_total), 0, 100))

    scores = [
        int(item["score"])
        for item in biomechanics
        if item.get("category") in cfg.PRIMARY_CATEGORIES
    ]
    if not scores:
        scores = [int(item["score"]) for item in biomechanics if int(item.get("score", 0) or 0) > 0]
    if not scores:
        return 0
    return int(np.clip(round(float(np.mean(scores))), 0, 100))


def analyze_biomechanics(
    all_landmarks: Any,
    fps: float = 30.0,
    personal_baseline: dict[str, Any] | None = None,
    *,
    sample_every: int = 1,
    shooting_hand_override: str | None = None,
) -> dict[str, Any]:
    """
    Detect shot phases with the AI temporal classifier, then score each
    biomechanics category only inside its phase window.

    personal_baseline: optional player baseline (ready after 20+ analyses).
    Personalized score adjustments apply only when PERSONALIZED_SCORING_ENABLED.

    shooting_hand_override: the user's own declared shooting hand ("left" or
    "right"), when known. Auto-detection (`resolve_clip_shooting_side`) votes
    on whichever wrist is more visible, which is wrong when the camera sits
    on the side opposite the shooting hand — that arm is partially occluded
    through the whole clip, biasing the vote toward the guide hand instead.
    The user's own answer is a far more reliable signal than anything
    inferable from occluded pose data, so it wins whenever it's available.
    """
    every = sample_every
    if isinstance(all_landmarks, dict) and all_landmarks.get("sample_every"):
        every = int(all_landmarks["sample_every"])

    frames = as_frames(all_landmarks)

    # Lock shooting side for the whole clip before phases/scoring so left/right
    # wrist jitter cannot flip arm metrics mid-analysis.
    if shooting_hand_override in ("left", "right"):
        clip_side = shooting_hand_override
    else:
        clip_side = resolve_clip_shooting_side(frames) if frames else "right"
    set_clip_shooting_side(clip_side)
    try:
        return _analyze_biomechanics_locked(
            all_landmarks,
            frames=frames,
            phases_fps=fps,
            sample_every=every,
            personal_baseline=personal_baseline,
            clip_side=clip_side,
        )
    finally:
        set_clip_shooting_side(None)


def _analyze_biomechanics_locked(
    all_landmarks: Any,
    *,
    frames: list[Any],
    phases_fps: float,
    sample_every: int,
    personal_baseline: dict[str, Any] | None,
    clip_side: str,
) -> dict[str, Any]:
    fps = phases_fps
    every = sample_every

    # Phase detection FIRST — biomechanics windows depend on these labels.
    phases = detect_shot_phases(all_landmarks, fps=fps, sample_every=every)

    if not frames:
        empty = {
            "score": 0,
            "status": "FAIL",
            "color": "RED",
            "measurement": "No pose detected",
            "issue": "No pose detected in this video",
            "correction": "Retake with your full body visible and good lighting",
            "timestamp": "00:00",
            "seconds": 0.0,
            "highlight": [],
        }
        biomechanics = [
            {"category": name, **empty}
            for name in (
                "Stance",
                "Load",
                "Ball Position",
                "Set Point",
                "Release",
                "Follow Through",
                "Balance",
            )
        ]
        return {
            "overall_score": 0,
            "biomechanics": biomechanics,
            "breakdown": biomechanics,
            "metrics": {
                "feet_stance": 0,
                "elbow_alignment": 0,
                "knee_bend": 0,
                "balance": 0,
                "follow_through": 0,
                "release_position": 0,
                "release_point": 0,
            },
            "timeline": timeline_entries(
                phases,
                {key: "FAIL" for key in (
                    "setup", "gather", "knee_load", "set_point",
                    "release", "follow_through", "landing",
                )},
            ),
            "frame_metrics": [],
            "frame_phases": phases.get("frame_phases", []),
            "phase_detector": phases.get("detector", {}),
            "issues": ["No pose detected in this video"],
            "recommendations": [
                "Retake with your full body visible and good lighting",
            ],
            "strengths": [],
            "phases": phases,
            "improvement_summary": "No pose detected in this video",
            "baseline_features": {},
            "measurement_confidence": {},
            "phase_landmarks": {},
            "personalization": {
                "enabled": PERSONALIZED_SCORING_ENABLED,
                "applied": False,
                "baseline_ready": False,
                "min_samples": 20,
            },
            "shooting_side": clip_side,
            "step": 5,
        }

    # Primary phase categories + Balance / Ball Position for interactive breakdown.
    biomechanics = [
        analyze_feet(all_landmarks, fps=fps, phases=phases),
        analyze_knees(all_landmarks, fps=fps, phases=phases),
        analyze_hand_position(all_landmarks, fps=fps, phases=phases),
        analyze_elbow(all_landmarks, fps=fps, phases=phases),
        analyze_release(all_landmarks, fps=fps, phases=phases),
        analyze_follow_through(all_landmarks, fps=fps, phases=phases),
        analyze_balance(all_landmarks, fps=fps, phases=phases),
    ]

    # Keep a stable interactive display order (Flutter MovementIssue catalog).
    display_order = (
        "Stance",
        "Load",
        "Ball Position",
        "Hand Position",
        "Set Point",
        "Release",
        "Follow Through",
        "Balance",
    )
    by_name = {item["category"]: item for item in biomechanics}
    ordered = [by_name[name] for name in display_order if name in by_name]
    # Deduplicate if Hand Position was renamed to Ball Position.
    seen: set[str] = set()
    biomechanics = []
    for item in ordered:
        cat = str(item.get("category", ""))
        if cat in seen:
            continue
        seen.add(cat)
        biomechanics.append(item)
    if not biomechanics:
        biomechanics = list(by_name.values())

    # Personalization hook (no-op on scores while flag is False).
    biomechanics, personalization_meta = apply_personalization(
        biomechanics,
        personal_baseline,
        enabled=PERSONALIZED_SCORING_ENABLED,
    )
    personalization_payload = build_analysis_personalization_payload(
        biomechanics,
        phases,
        all_landmarks,
        baseline=personal_baseline,
    )
    personalization_payload["personalization"] = {
        **personalization_payload.get("personalization", {}),
        **personalization_meta,
    }

    overall = _average_overall(biomechanics)

    def _score(*names: str) -> int:
        for item in biomechanics:
            if item["category"] in names:
                return int(item["score"])
        return 0

    # Persist under legacy metric keys so Flutter Progress / History keep working.
    stance_score = _score("Stance", "Feet & Stance")
    load_score = _score("Load", "Knee Bend")
    set_score = _score("Set Point", "Elbow Alignment")
    release_score = _score("Release", "Release Point", "Release Position")
    follow_score = _score("Follow Through")
    balance_score = _score("Balance") or stance_score
    ball_score = _score("Ball Position", "Hand Position") or release_score
    metrics = {
        "stance": stance_score,
        "load": load_score,
        "set_point": set_score,
        "release": release_score,
        "follow_through": follow_score,
        # Legacy aliases
        "feet_stance": stance_score,
        "knee_bend": load_score,
        "elbow_alignment": set_score,
        "balance": balance_score,
        "release_position": ball_score,
        "release_point": release_score,
    }

    timeline_status = {
        "setup": _status(biomechanics, "Stance", "Feet & Stance"),
        "gather": _status(biomechanics, "Load", "Stance"),
        "knee_load": _status(biomechanics, "Load", "Knee Bend"),
        "set_point": _status(biomechanics, "Set Point", "Elbow Alignment"),
        "release": _status(biomechanics, "Release", "Release Point"),
        "follow_through": _status(biomechanics, "Follow Through"),
        "landing": _status(biomechanics, "Follow Through", "Stance"),
    }

    strengths = [i["category"] for i in biomechanics if i["status"] == "PASS"]
    issues = [i["issue"] for i in biomechanics if i["status"] != "PASS"]
    recommendations = [
        i["correction"] for i in biomechanics if i["status"] != "PASS"
    ]
    # Explicit point-loss rows for Results “Why You Lost Points”.
    ideal_floor = 92
    point_losses = []
    for item in biomechanics:
        score = int(item.get("score", 0) or 0)
        lost = max(0, ideal_floor - score)
        if lost < 4 or score <= 0:
            continue
        point_losses.append(
            {
                "category": item.get("category"),
                "score": score,
                "points_lost": lost,
                "reason": item.get("issue")
                or f"Below ideal form in {item.get('category')}",
                "measurement": item.get("measurement"),
                "correction": item.get("correction"),
            }
        )
    point_losses.sort(key=lambda row: int(row["points_lost"]), reverse=True)
    point_losses = point_losses[:5]
    priority_improvements = []
    for idx, row in enumerate(point_losses[:3], start=1):
        priority_improvements.append(
            {
                "rank": idx,
                "category": row["category"],
                "score": row["score"],
                "observation": row["reason"],
                "fix": row.get("correction")
                or "Own one short cue and rebuild to game speed.",
                "points_lost": row["points_lost"],
            }
        )

    timeline = enrich_timeline_with_spans(
        phases,
        timeline_entries(phases, timeline_status),
        all_landmarks,
        fps=fps,
    )
    frame_metrics = build_frame_metrics(all_landmarks, phases, fps=fps)

    print(
        "Biomechanics engine (phase-aware):",
        f"overall={overall}",
        f"side={clip_side}",
        f"phases={[ (k, phases[k]['timestamp']) for k in ('setup','gather','knee_load','release','follow_through','landing') if k in phases ]}",
        f"categories={[(b['category'], b['score'], b['color'], b.get('phase_key')) for b in biomechanics]}",
        f"frame_metrics={len(frame_metrics)}",
    )

    return {
        "overall_score": overall,
        "biomechanics": biomechanics,
        "breakdown": biomechanics,
        "metrics": metrics,
        "timeline": timeline,
        "frame_metrics": frame_metrics,
        "frame_phases": phases.get("frame_phases", []),
        "phase_detector": phases.get("detector", {}),
        "issues": issues,
        "recommendations": recommendations
        or [b["correction"] for b in biomechanics[:2]],
        "strengths": strengths,
        "phases": phases,
        "point_losses": point_losses,
        "priority_improvements": priority_improvements,
        "improvement_summary": (
            issues[0]
            if issues
            else "Solid mechanics overall — protect your strengths under game speed."
        ),
        "baseline_features": personalization_payload.get("baseline_features", {}),
        "measurement_confidence": personalization_payload.get(
            "measurement_confidence", {}
        ),
        "phase_landmarks": personalization_payload.get("phase_landmarks", {}),
        "personalization": personalization_payload.get("personalization", {}),
        "shooting_side": clip_side,
        "step": 5,
    }


def _status(biomechanics: list[dict[str, Any]], *names: str) -> str:
    for item in biomechanics:
        if item["category"] in names:
            return str(item.get("status", "PASS"))
    return "PASS"


def _worst_status(*statuses: str) -> str:
    order = {"FAIL": 0, "WARN": 1, "NEEDS_WORK": 1, "PASS": 2}
    return min(statuses, key=lambda s: order.get(s, 1))


def analyze_shot_mechanics(
    all_landmarks: Any,
    fps: float = 30.0,
    personal_baseline: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return analyze_biomechanics(
        all_landmarks,
        fps=fps,
        personal_baseline=personal_baseline,
    )
