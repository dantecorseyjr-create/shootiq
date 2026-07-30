"""
Follow-Through & Elbow Alignment Analyzer
-------------------------------------------
Takes the JSON output from shot_pose_extractor.py and analyzes two things:

1. ELBOW ALIGNMENT — how well the shooting elbow stays "under the ball"
   (in line with shoulder and wrist) instead of flaring out to the side,
   measured across the rise-to-release window.

2. FOLLOW-THROUGH — detects the release frame, then checks how long and
   how well the wrist-snap / arm-extension position is held afterward
   (the "reach into the cookie jar and hold it" pose).

USAGE:
    python follow_through_analyzer.py shot_angles.json
    python follow_through_analyzer.py shot_angles.json --side right
    python follow_through_analyzer.py shot_angles.json --output analysis.json

Also used by pose_pipeline.py after shot_angles.json is written.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np


def get_side(data: dict[str, Any], requested: str | None = None) -> str:
    """Auto-detect which side (left/right) has better visibility if not specified."""
    if requested:
        return requested

    # Prefer clip-locked side from biomechanics when available.
    try:
        from pose_utils import get_clip_shooting_side, resolve_clip_shooting_side

        locked = get_clip_shooting_side()
        if locked in ("left", "right"):
            return locked
        landmark_frames = [
            f["landmarks"]
            for f in (data.get("frames") or [])
            if isinstance(f.get("landmarks"), dict) and f["landmarks"]
        ]
        if landmark_frames:
            return resolve_clip_shooting_side(landmark_frames)
    except Exception:  # noqa: BLE001
        pass

    frames = data.get("frames") or []
    left_vis: list[float] = []
    right_vis: list[float] = []
    for f in frames:
        lm = f.get("landmarks", {})
        if "left_wrist" in lm:
            left_vis.append(float(lm["left_wrist"]["visibility"]))
        if "right_wrist" in lm:
            right_vis.append(float(lm["right_wrist"]["visibility"]))

    left_avg = float(np.mean(left_vis)) if left_vis else 0.0
    right_avg = float(np.mean(right_vis)) if right_vis else 0.0
    return "right" if right_avg >= left_avg else "left"


def elbow_flare_angle(frame: dict[str, Any], side: str) -> float | None:
    """
    Measures how far the elbow sits away from the vertical shoulder-wrist
    line (a proxy for "elbow under the ball" vs "elbow flared out").

    Uses the horizontal (x) offset of the elbow relative to the straight
    line between shoulder and wrist, normalized by torso width so it's
    scale-independent. 0 = perfectly in line. Higher = more flare.
    """
    lm = frame.get("landmarks", {})
    required = [
        f"{side}_shoulder",
        f"{side}_elbow",
        f"{side}_wrist",
        "left_shoulder",
        "right_shoulder",
    ]
    if not all(k in lm for k in required):
        return None

    shoulder = np.array(
        [lm[f"{side}_shoulder"]["x"], lm[f"{side}_shoulder"]["y"]],
        dtype=float,
    )
    elbow = np.array(
        [lm[f"{side}_elbow"]["x"], lm[f"{side}_elbow"]["y"]],
        dtype=float,
    )
    wrist = np.array(
        [lm[f"{side}_wrist"]["x"], lm[f"{side}_wrist"]["y"]],
        dtype=float,
    )

    # shoulder width as a normalizing scale (accounts for distance from camera)
    ls = np.array(
        [lm["left_shoulder"]["x"], lm["left_shoulder"]["y"]],
        dtype=float,
    )
    rs = np.array(
        [lm["right_shoulder"]["x"], lm["right_shoulder"]["y"]],
        dtype=float,
    )
    shoulder_width = float(np.linalg.norm(ls - rs) + 1e-9)

    # perpendicular distance from elbow to the shoulder-wrist line
    line_vec = wrist - shoulder
    line_len = float(np.linalg.norm(line_vec) + 1e-9)
    line_unit = line_vec / line_len
    point_vec = elbow - shoulder
    proj_len = float(np.dot(point_vec, line_unit))
    proj_point = shoulder + proj_len * line_unit
    perp_dist = float(np.linalg.norm(elbow - proj_point))

    normalized_flare = perp_dist / shoulder_width
    return round(normalized_flare, 4)


def find_release_frame(data: dict[str, Any], side: str) -> int | None:
    """
    Estimate the release frame as the point of maximum wrist angle
    (fullest extension/snap) within the clip — a simple heuristic until
    ball-tracking is added.
    """
    frames = data.get("frames") or []
    wrist_key = f"{side}_wrist"

    candidates = [
        (int(f["frame"]), float(f["angles"][wrist_key]))
        for f in frames
        if "angles" in f and wrist_key in (f.get("angles") or {})
    ]
    if not candidates:
        return None

    release_frame, _ = max(candidates, key=lambda c: c[1])
    return release_frame


def analyze_elbow_alignment(data: dict[str, Any], side: str) -> dict[str, Any]:
    frames = data.get("frames") or []
    flare_series: list[dict[str, Any]] = []

    for f in frames:
        flare = elbow_flare_angle(f, side)
        if flare is not None:
            flare_series.append(
                {
                    "frame": f["frame"],
                    "time_sec": f["time_sec"],
                    "flare": flare,
                }
            )

    if not flare_series:
        return {"error": "No usable landmark data for elbow alignment analysis."}

    flares = [x["flare"] for x in flare_series]
    avg_flare = round(float(np.mean(flares)), 4)
    max_flare_entry = max(flare_series, key=lambda x: x["flare"])

    # rough qualitative bands based on normalized flare value
    if avg_flare < 0.08:
        rating = "tight / well-aligned"
    elif avg_flare < 0.16:
        rating = "slightly flared"
    else:
        rating = "notably flared"

    return {
        "average_flare": avg_flare,
        "rating": rating,
        "worst_frame": max_flare_entry["frame"],
        "worst_time_sec": max_flare_entry["time_sec"],
        "worst_flare_value": max_flare_entry["flare"],
        "frame_by_frame": flare_series,
        "note": (
            "flare is normalized by shoulder width; 0 = elbow perfectly in "
            "line between shoulder and wrist, higher = more sideways flare."
        ),
    }


def analyze_follow_through_hold(
    data: dict[str, Any],
    side: str,
    hold_window: int = 15,
) -> dict[str, Any]:
    """
    Post-release hold quality from shot_angles.json.

    Named distinctly from followthrough_analyzer.analyze_follow_through
    (phase-aware biomechanics scorer).
    """
    frames = data.get("frames") or []
    wrist_key = f"{side}_wrist"
    elbow_key = f"{side}_elbow"

    release_frame = find_release_frame(data, side)
    if release_frame is None:
        return {"error": "Could not determine release frame."}

    post_release = [
        f
        for f in frames
        if f["frame"] >= release_frame
        and f["frame"] <= release_frame + hold_window
        and "angles" in f
        and wrist_key in f["angles"]
        and elbow_key in f["angles"]
    ]

    if not post_release:
        return {
            "error": "No frames found after release for follow-through analysis."
        }

    wrist_angles = [f["angles"][wrist_key] for f in post_release]
    elbow_angles = [f["angles"][elbow_key] for f in post_release]

    release_wrist_angle = wrist_angles[0]
    release_elbow_angle = elbow_angles[0]

    # how much the wrist/elbow angle drifts after release (lower drift = better hold)
    wrist_drift = round(float(np.std(wrist_angles)), 2)
    elbow_drift = round(float(np.std(elbow_angles)), 2)

    # crude "held the pose" check: angles stay within a tight band
    held_well = wrist_drift < 8 and elbow_drift < 8
    fps = float(data.get("fps") or 30.0)

    return {
        "release_frame": release_frame,
        "release_time_sec": round(release_frame / max(fps, 1e-6), 3),
        "release_wrist_angle": release_wrist_angle,
        "release_elbow_angle": release_elbow_angle,
        "wrist_angle_drift_after_release": wrist_drift,
        "elbow_angle_drift_after_release": elbow_drift,
        "held_follow_through_well": held_well,
        "frames_analyzed_after_release": len(post_release),
        "note": (
            "Drift is the standard deviation of the angle across the frames "
            "following release. Lower drift means the arm held its position "
            "(good follow-through); higher drift means the arm dropped or "
            "moved early."
        ),
    }


# CLI / docs alias matching the original script name.
analyze_follow_through = analyze_follow_through_hold


def run_follow_through_analysis(
    data: dict[str, Any],
    *,
    side: str | None = None,
    hold_window: int = 15,
    source_file: str | None = None,
) -> dict[str, Any]:
    """Run elbow-alignment + follow-through hold analysis on shot_angles data."""
    resolved_side = get_side(data, side)
    elbow_result = analyze_elbow_alignment(data, resolved_side)
    follow_through_result = analyze_follow_through_hold(
        data, resolved_side, hold_window=hold_window
    )
    return {
        "source_file": source_file,
        "shooting_side": resolved_side,
        "elbow_alignment": elbow_result,
        "follow_through": follow_through_result,
    }


def analyze_shot_angles_file(
    input_path: str | Path,
    *,
    side: str | None = None,
    hold_window: int = 15,
    output_path: str | Path | None = None,
) -> dict[str, Any]:
    """Load shot_angles.json, analyze, optionally write JSON, return payload."""
    input_path = Path(input_path)
    with open(input_path, encoding="utf-8") as f:
        data = json.load(f)

    output = run_follow_through_analysis(
        data,
        side=side,
        hold_window=hold_window,
        source_file=str(input_path),
    )

    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            json.dump(output, f, indent=2)

    return output


def enrich_biomechanics_with_angle_analysis(
    biomechanics: list[dict[str, Any]],
    analysis: dict[str, Any],
) -> list[dict[str, Any]]:
    """
    Attach flare/hold metrics onto Set Point / Elbow and Follow Through rows
    without changing their primary scores.
    """
    elbow = analysis.get("elbow_alignment") or {}
    follow = analysis.get("follow_through") or {}
    out: list[dict[str, Any]] = []

    for item in biomechanics:
        entry = dict(item)
        features = dict(entry.get("features") or {})
        cat = str(entry.get("category", "")).lower()

        if "error" not in elbow and ("set point" in cat or "elbow" in cat):
            features["elbow_flare_avg"] = float(elbow.get("average_flare") or 0)
            features["elbow_flare_worst"] = float(
                elbow.get("worst_flare_value") or 0
            )
            entry["features"] = features
            # Prefer the worst-flare moment for review seek when available.
            if elbow.get("worst_time_sec") is not None:
                stamp = float(elbow["worst_time_sec"])
                entry["seconds"] = stamp
                mins = int(stamp // 60)
                secs = int(round(stamp % 60))
                entry["timestamp"] = f"{mins:02d}:{secs:02d}"
            note = elbow.get("rating")
            if note:
                base_m = str(entry.get("measurement") or "").strip()
                flare_m = f"flare {note} ({elbow.get('average_flare')})"
                entry["measurement"] = (
                    f"{base_m} · {flare_m}" if base_m else f"Elbow {flare_m}"
                )

        if "error" not in follow and "follow" in cat:
            features["wrist_drift"] = float(
                follow.get("wrist_angle_drift_after_release") or 0
            )
            features["elbow_drift"] = float(
                follow.get("elbow_angle_drift_after_release") or 0
            )
            features["held_follow_through"] = (
                1.0 if follow.get("held_follow_through_well") else 0.0
            )
            entry["features"] = features
            held = follow.get("held_follow_through_well")
            drift = follow.get("wrist_angle_drift_after_release")
            if held is not None:
                hold_txt = "held" if held else "dropped early"
                base_m = str(entry.get("measurement") or "").strip()
                hold_m = f"follow-through {hold_txt} (wrist drift {drift}°)"
                entry["measurement"] = (
                    f"{base_m} · {hold_m}" if base_m else hold_m
                )

        out.append(entry)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analyze elbow alignment and follow-through from pose JSON."
    )
    parser.add_argument(
        "input",
        help="Path to shot_angles.json produced by shot_pose_extractor.py",
    )
    parser.add_argument(
        "--side",
        choices=["left", "right"],
        default=None,
        help="Which arm is the shooting arm (auto-detected if omitted)",
    )
    parser.add_argument(
        "--output",
        default="follow_through_analysis.json",
        help="Path to output JSON file",
    )
    parser.add_argument(
        "--hold-window",
        type=int,
        default=15,
        help="Number of frames after release to evaluate for follow-through hold",
    )
    args = parser.parse_args()

    output = analyze_shot_angles_file(
        args.input,
        side=args.side,
        hold_window=args.hold_window,
        output_path=args.output,
    )

    side = output["shooting_side"]
    print(f"Using '{side}' as the shooting side.")
    print(f"\nAnalysis written to: {args.output}")

    elbow_result = output["elbow_alignment"]
    follow_through_result = output["follow_through"]

    if "error" not in elbow_result:
        print(
            f"\nElbow alignment: {elbow_result['rating']} "
            f"(avg flare {elbow_result['average_flare']})"
        )
        print(
            f"  Worst flare at frame {elbow_result['worst_frame']} "
            f"({elbow_result['worst_time_sec']}s)"
        )

    if "error" not in follow_through_result:
        print(
            f"\nRelease detected at frame {follow_through_result['release_frame']} "
            f"({follow_through_result['release_time_sec']}s)"
        )
        print(
            f"  Wrist angle at release: "
            f"{follow_through_result['release_wrist_angle']}°"
        )
        print(
            f"  Wrist drift after release: "
            f"{follow_through_result['wrist_angle_drift_after_release']}°"
        )
        print(
            f"  Held follow-through well: "
            f"{follow_through_result['held_follow_through_well']}"
        )


if __name__ == "__main__":
    main()
