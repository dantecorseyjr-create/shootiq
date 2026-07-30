"""
Shot Scorer v4 — CALIBRATION DIAGNOSTICS (read-only).

Does NOT change scoring, weights, thresholds, coaching, or API response shape.
Re-runs the same measurement helpers used by shot_scorer.py and prints / saves
a full breakdown so we can see exactly where points are lost.

USAGE:
    python shot_score_diagnostics.py path/to/shot_angles.json \\
        --video path/to/video.mp4 \\
        --output-dir path/to/diagnostics_out

Or from code:
    from shot_score_diagnostics import run_diagnostics
    run_diagnostics(angles_payload, video_path=..., output_dir=...)
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Optional

import numpy as np

from shot_scorer import (
    METRIC_DEFS,
    SECTIONS,
    TOLERANCE_BANDS,
    band_score,
    ball_position_centering_value,
    ball_position_height_value,
    elbow_flare_value,
    find_load_frame,
    find_release_frame_velocity,
    foot_stance_width_value,
    get_side,
    hip_balance_lean_value,
    joints_visible,
    safe_shoulder_width,
    score_single_shot,
)

# Slightly outside band but still taking max deduction → over-penalizing signal.
SLIGHT_OVERSHOOT_FRACTION = 0.25  # within 25% of band width past the edge


def _section_for_metric(metric: str) -> tuple[str, str]:
    for key, sec in SECTIONS.items():
        if metric in sec["metrics"]:
            return key, sec["label"]
    return "unknown", metric


def _max_points_for(metric: str) -> float:
    for sec in SECTIONS.values():
        if metric in sec["metrics"]:
            return sec["max_points"] / len(sec["metrics"])
    return 0.0


def _fmt(value: Any, unit: str = "") -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        text = f"{value:.4g}"
    else:
        text = str(value)
    return f"{text}{unit}"


def collect_metric_rows(data: dict, side: str, hold_seconds: float = 0.5) -> dict[str, Any]:
    """
    Mirror score_single_shot measurement paths (without changing scoring) and
    return per-metric measured values + deductions for diagnostics.
    """
    frames = data["frames"]
    frame_lookup = {f["frame"]: f for f in frames}
    load_frame_num = find_load_frame(frames, side)
    release_frame_num = find_release_frame_velocity(frames, side, load_frame_num)

    rows: list[dict[str, Any]] = []

    def add_row(metric: str, value: Any, frame_num: Optional[int], note: str = ""):
        band = TOLERANCE_BANDS[metric]
        section_key, section_label = _section_for_metric(metric)
        if value is None:
            rows.append({
                "metric": metric,
                "section_key": section_key,
                "section_label": section_label,
                "value": None,
                "frame": frame_num,
                "time_sec": frame_lookup.get(frame_num, {}).get("time_sec") if frame_num is not None else None,
                "ideal_low": band["low"],
                "ideal_high": band["high"],
                "max_deduction": band["max_deduction"],
                "deduction": None,
                "verdict": "missing / unreliable",
                "points_available": _max_points_for(metric),
                "points_earned": None,
                "note": note,
                "over_penalizing": False,
            })
            return

        ded, verdict = band_score(float(value), band)
        pts = _max_points_for(metric)
        span = max(band["high"] - band["low"], 1e-6)
        if value < band["low"]:
            overshoot = band["low"] - value
        elif value > band["high"]:
            overshoot = value - band["high"]
        else:
            overshoot = 0.0
        over_penalizing = (
            ded is not None
            and ded >= band["max_deduction"]
            and overshoot > 0
            and overshoot <= span * SLIGHT_OVERSHOOT_FRACTION
        )
        rows.append({
            "metric": metric,
            "section_key": section_key,
            "section_label": section_label,
            "value": float(value) if isinstance(value, (int, float, np.floating)) else value,
            "frame": frame_num,
            "time_sec": frame_lookup.get(frame_num, {}).get("time_sec") if frame_num is not None else None,
            "ideal_low": band["low"],
            "ideal_high": band["high"],
            "max_deduction": band["max_deduction"],
            "deduction": ded,
            "verdict": verdict,
            "points_available": pts,
            "points_earned": round(pts - ded, 2),
            "note": note,
            "over_penalizing": over_penalizing,
            "overshoot": round(overshoot, 4),
            "band_span": round(span, 4),
        })

    # Simple load/release metrics
    for metric, (req_fn, value_fn, ref) in METRIC_DEFS.items():
        ref_frame_num = load_frame_num if ref == "load" else release_frame_num
        if ref_frame_num is None or ref_frame_num not in frame_lookup:
            add_row(metric, None, ref_frame_num, note="missing reference frame")
            continue
        frame = frame_lookup[ref_frame_num]
        if not joints_visible(frame, req_fn(side)):
            add_row(metric, None, ref_frame_num, note="joints not visible")
            continue
        value = value_fn(frame, side)
        add_row(metric, value, ref_frame_num)

    # elbow_flare
    if load_frame_num is not None and release_frame_num is not None:
        req = [f"{side}_shoulder", f"{side}_elbow", f"{side}_wrist", "left_shoulder", "right_shoulder"]
        window = [f for f in frames if load_frame_num <= f["frame"] <= release_frame_num]
        raw_flares = [(f["frame"], elbow_flare_value(f, side)) for f in window if joints_visible(f, req)]
        flares = [(fr, v) for fr, v in raw_flares if v is not None]
        if flares:
            worst_frame, worst_val = max(flares, key=lambda x: x[1])
            add_row("elbow_flare", worst_val, worst_frame, note="worst in load→release window")
        else:
            add_row("elbow_flare", None, None, note="no reliable flare samples")
    else:
        add_row("elbow_flare", None, None, note="missing load/release")

    # wrist_snap_range
    if load_frame_num is not None and release_frame_num is not None:
        lf, rf = frame_lookup.get(load_frame_num), frame_lookup.get(release_frame_num)
        req = [f"{side}_elbow", f"{side}_wrist", f"{side}_index"]
        if lf and rf and joints_visible(lf, req) and joints_visible(rf, req):
            snap_range = abs(rf["angles"][f"{side}_wrist"] - lf["angles"][f"{side}_wrist"])
            add_row("wrist_snap_range", snap_range, release_frame_num, note="|release_wrist - load_wrist|")
        else:
            add_row("wrist_snap_range", None, release_frame_num, note="joints not visible")
    else:
        add_row("wrist_snap_range", None, None, note="missing load/release")

    # follow_through_drift
    if release_frame_num is not None:
        req = [f"{side}_elbow", f"{side}_wrist", f"{side}_index", f"{side}_shoulder"]
        release_time = next((f["time_sec"] for f in frames if f["frame"] == release_frame_num), None)
        hold_end_time = (release_time + hold_seconds) if release_time is not None else None
        post = [f for f in frames if f["frame"] >= release_frame_num
                and (hold_end_time is None or f["time_sec"] <= hold_end_time)
                and "angles" in f and f"{side}_wrist" in f["angles"] and f"{side}_elbow" in f["angles"]
                and joints_visible(f, req)]
        if len(post) >= 3:
            drift = max(float(np.std([f["angles"][f"{side}_wrist"] for f in post])),
                        float(np.std([f["angles"][f"{side}_elbow"] for f in post])))
            add_row("follow_through_drift", drift, release_frame_num, note=f"std over {hold_seconds}s post-release")
        else:
            add_row("follow_through_drift", None, release_frame_num, note="insufficient post-release frames")
    else:
        add_row("follow_through_drift", None, None, note="missing release")

    # hip_balance_lean
    if release_frame_num is not None:
        req = [f"{side}_shoulder", f"{side}_hip", f"{side}_ankle"]
        rf = frame_lookup[release_frame_num]
        if joints_visible(rf, req):
            lean = hip_balance_lean_value(rf, side)
            add_row("hip_balance_lean", lean, release_frame_num)
        else:
            add_row("hip_balance_lean", None, release_frame_num, note="joints not visible")
    else:
        add_row("hip_balance_lean", None, None, note="missing release")

    # Raw context at load / release
    raw: dict[str, Any] = {
        "shooting_side": side,
        "load_frame": load_frame_num,
        "release_frame": release_frame_num,
    }
    if load_frame_num is not None and load_frame_num in frame_lookup:
        lf = frame_lookup[load_frame_num]
        lm = lf.get("landmarks") or {}
        if "left_shoulder" in lm and "right_shoulder" in lm:
            width, reliable = safe_shoulder_width(lm)
            raw["shoulder_width_3d"] = width
            raw["shoulder_width_reliable"] = reliable
        if joints_visible(lf, ["left_ankle", "right_ankle", "left_shoulder", "right_shoulder"]):
            raw["foot_stance"] = foot_stance_width_value(lf)
        if f"{side}_knee" in (lf.get("angles") or {}):
            raw["knee_angle_load"] = lf["angles"][f"{side}_knee"]
        if f"{side}_elbow" in (lf.get("angles") or {}):
            raw["elbow_angle_load"] = lf["angles"][f"{side}_elbow"]
        if f"{side}_wrist" in (lf.get("angles") or {}):
            raw["wrist_angle_load"] = lf["angles"][f"{side}_wrist"]
        if joints_visible(lf, [f"{side}_wrist", "nose", "left_shoulder", "right_shoulder"]):
            raw["ball_height"] = ball_position_height_value(lf, side)
            raw["ball_centering"] = ball_position_centering_value(lf, side)
        raw["load_time_sec"] = lf.get("time_sec")

    if release_frame_num is not None and release_frame_num in frame_lookup:
        rf = frame_lookup[release_frame_num]
        if f"{side}_elbow" in (rf.get("angles") or {}):
            raw["elbow_angle_release"] = rf["angles"][f"{side}_elbow"]
        if f"{side}_wrist" in (rf.get("angles") or {}):
            raw["wrist_angle_release"] = rf["angles"][f"{side}_wrist"]
        if joints_visible(rf, [f"{side}_shoulder", f"{side}_hip", f"{side}_ankle"]):
            raw["hip_lean_release"] = hip_balance_lean_value(rf, side)
        raw["release_time_sec"] = rf.get("time_sec")

    # Knee-curve sanity: is load frame the min knee angle?
    knee_series = [
        (f["frame"], f["time_sec"], f["angles"].get(f"{side}_knee"))
        for f in frames
        if "angles" in f and f"{side}_knee" in f["angles"]
    ]
    knee_series = [(fr, t, k) for fr, t, k in knee_series if k is not None]
    true_min_knee = min(knee_series, key=lambda x: x[2]) if knee_series else None

    return {
        "load_frame": load_frame_num,
        "release_frame": release_frame_num,
        "rows": rows,
        "raw": raw,
        "true_min_knee": true_min_knee,
        "frames": frames,
        "side": side,
    }


def _print_raw_values(raw: dict[str, Any]) -> None:
    print("\n=========================")
    print("RAW MEASUREMENTS (pre-score)")
    print("=========================")
    print(f"Shoulder width:     {_fmt(raw.get('shoulder_width_3d'))}"
          f"  (reliable={raw.get('shoulder_width_reliable')})")
    print(f"Foot stance:        {_fmt(raw.get('foot_stance'))}")
    print(f"Knee angle (load):  {_fmt(raw.get('knee_angle_load'), '°')}")
    print(f"Elbow (load):       {_fmt(raw.get('elbow_angle_load'), '°')}")
    print(f"Wrist (load):       {_fmt(raw.get('wrist_angle_load'), '°')}")
    print(f"Ball height:        {_fmt(raw.get('ball_height'))}")
    print(f"Ball centering:     {_fmt(raw.get('ball_centering'))}")
    print(f"Elbow (release):    {_fmt(raw.get('elbow_angle_release'), '°')}")
    print(f"Wrist (release):    {_fmt(raw.get('wrist_angle_release'), '°')}")
    print(f"Release extension:  {_fmt(raw.get('elbow_angle_release'), '°')}  (same as elbow@release)")
    print(f"Hip lean:           {_fmt(raw.get('hip_lean_release'), '°')}")


def _print_load_release(diag: dict[str, Any]) -> None:
    raw = diag["raw"]
    side = diag["side"]
    print("\n=========================")
    print("LOAD FRAME CHECK")
    print("=========================")
    print(f"Load frame:   {diag['load_frame']}")
    print(f"Knee angle:   {_fmt(raw.get('knee_angle_load'), '°')}")
    print(f"Time:         {_fmt(raw.get('load_time_sec'), ' s')}")
    tmk = diag.get("true_min_knee")
    if tmk is not None:
        print(f"True min knee in clip: frame={tmk[0]} angle={tmk[2]:.2f}° time={tmk[1]:.3f}s")
        if diag["load_frame"] == tmk[0]:
            print("OK: load frame == deepest knee bend in clip")
        else:
            print("WARNING: load frame is NOT the deepest knee bend in the full clip "
                  "(may be intentional if ascent-capped)")

    print("\n=========================")
    print("RELEASE FRAME CHECK")
    print("=========================")
    print(f"Release frame: {diag['release_frame']}")
    print(f"Elbow:         {_fmt(raw.get('elbow_angle_release'), '°')}")
    print(f"Wrist:         {_fmt(raw.get('wrist_angle_release'), '°')}")
    print(f"Time:          {_fmt(raw.get('release_time_sec'), ' s')}")
    print(f"Shooting side: {side}")


def _print_deductions(rows: list[dict[str, Any]]) -> None:
    print("\n=========================")
    print("EVERY DEDUCTION")
    print("=========================")
    by_section: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        by_section.setdefault(row["section_label"], []).append(row)

    for section_label, section_rows in by_section.items():
        print(f"\n{section_label}")
        print("-" * len(section_label))
        for row in section_rows:
            print(f"\n  Metric:     {row['metric']}")
            print(f"  Measured:   {_fmt(row['value'])}")
            print(f"  Expected:   {row['ideal_low']}–{row['ideal_high']}")
            print(f"  Deduction:  {_fmt(row['deduction'])} points "
                  f"(max {row['max_deduction']})")
            print(f"  Reason:     {row['verdict']}")
            if row.get("note"):
                print(f"  Note:       {row['note']}")
            if row.get("over_penalizing"):
                print("  !! OVER-PENALIZING: max deduction for only slight overshoot")


def _print_comparison_table(rows: list[dict[str, Any]]) -> None:
    print("\n=========================")
    print("DEDUCTION COMPARISON")
    print("=========================")
    print(f"{'Metric':<28} {'Measured':>10} {'Ideal':>16} {'Deduction':>10}")
    print("-" * 68)
    for row in rows:
        ideal = f"{row['ideal_low']}–{row['ideal_high']}"
        measured = _fmt(row["value"])
        ded = _fmt(row["deduction"])
        print(f"{row['metric']:<28} {measured:>10} {ideal:>16} {ded:>10}")


def _print_section_breakdown(score_result: dict[str, Any]) -> None:
    print("\n=========================")
    print("FINAL SCORE BREAKDOWN")
    print("=========================\n")
    sections = score_result.get("sections") or {}
    earned_total = 0.0
    max_total = 0.0
    for key, sec_def in SECTIONS.items():
        sec = sections.get(key) or {}
        score = sec.get("score")
        max_pts = sec_def["max_points"]
        label = sec_def["label"]
        if score is None:
            print(f"{label}")
            print(f"n/a / {max_pts}  (not computed)\n")
        else:
            print(f"{label}")
            print(f"{score} / {max_pts}\n")
            earned_total += float(score)
            max_total += float(max_pts)

    overall = score_result.get("overall_score")
    print("Overall:")
    if overall is None:
        print(f"n/a / 100  (confidence={score_result.get('confidence')} "
              f"metrics={score_result.get('metrics_computed')})")
    else:
        # Show earned/available among computed sections AND overall_score field
        print(f"{overall} / 100")
        if max_total:
            print(f"(raw section sum: {earned_total:.1f} / {max_total:.0f} "
                  f"→ scaled overall {overall})")


def _print_threshold_warning(rows: list[dict[str, Any]]) -> None:
    ded_by_section: dict[str, float] = {}
    total = 0.0
    for row in rows:
        ded = row.get("deduction")
        if ded is None or ded <= 0:
            continue
        ded_by_section[row["section_label"]] = ded_by_section.get(row["section_label"], 0.0) + float(ded)
        total += float(ded)

    if total <= 0:
        print("\nNo positive deductions — threshold concentration N/A.")
        return

    print("\n=========================")
    print("DEDUCTION CONCENTRATION")
    print("=========================")
    ranked = sorted(ded_by_section.items(), key=lambda x: -x[1])
    for label, ded in ranked:
        pct = 100.0 * ded / total
        print(f"  {label}: {ded:.2f} pts ({pct:.1f}% of all deductions)")
        if pct > 60:
            print()
            print("WARNING")
            print()
            print(f"{label} accounts for {pct:.0f}% of all deductions.")
            print()
            print("Thresholds may be too strict.")

    overs = [r for r in rows if r.get("over_penalizing")]
    if overs:
        print("\n=========================")
        print("IMPOSSIBLE / OVER-AGGRESSIVE DEDUCTIONS")
        print("=========================")
        for row in overs:
            print(f"  {row['metric']}: value={_fmt(row['value'])} "
                  f"ideal={row['ideal_low']}–{row['ideal_high']} "
                  f"deduction={row['deduction']} (MAX) "
                  f"overshoot={row.get('overshoot')} vs span={row.get('band_span')}")


def _save_phase_frames(
    video_path: Optional[str],
    load_frame: Optional[int],
    release_frame: Optional[int],
    output_dir: Path,
    frames: list[dict],
) -> dict[str, Optional[str]]:
    """Extract and save load/release frame images from video if available."""
    out: dict[str, Optional[str]] = {"load_image": None, "release_image": None}
    if not video_path:
        print("\n(No --video provided; skipping load/release frame image export)")
        return out

    try:
        import cv2
    except ImportError:
        print("\n(cv2 not available; skipping frame image export)")
        return out

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"\n(Could not open video: {video_path})")
        return out

    frame_lookup = {f["frame"]: f for f in frames}

    def grab(frame_num: Optional[int], label: str) -> Optional[str]:
        if frame_num is None:
            return None
        # Prefer seeking by time for variable fps; fall back to frame index.
        time_sec = frame_lookup.get(frame_num, {}).get("time_sec")
        if time_sec is not None:
            cap.set(cv2.CAP_PROP_POS_MSEC, float(time_sec) * 1000.0)
        else:
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(frame_num))
        ok, img = cap.read()
        if not ok or img is None:
            print(f"(Failed to read {label} frame {frame_num})")
            return None
        # Annotate
        cv2.putText(
            img,
            f"{label} frame={frame_num} t={time_sec}",
            (20, 40),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (0, 255, 255),
            2,
            cv2.LINE_AA,
        )
        path = output_dir / f"{label}_frame_{frame_num}.jpg"
        cv2.imwrite(str(path), img)
        print(f"Saved {label} frame image: {path}")
        return str(path)

    out["load_image"] = grab(load_frame, "load")
    out["release_image"] = grab(release_frame, "release")
    cap.release()
    return out


def _save_metric_plots(
    frames: list[dict],
    side: str,
    load_frame: Optional[int],
    release_frame: Optional[int],
    output_dir: Path,
) -> Optional[str]:
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as exc:  # noqa: BLE001
        print(f"\n(Could not plot metrics: {exc})")
        return None

    times, elbows, wrists, knees, leans = [], [], [], [], []
    for f in frames:
        t = f.get("time_sec")
        if t is None:
            continue
        angles = f.get("angles") or {}
        times.append(t)
        elbows.append(angles.get(f"{side}_elbow"))
        wrists.append(angles.get(f"{side}_wrist"))
        knees.append(angles.get(f"{side}_knee"))
        lean = None
        try:
            if joints_visible(f, [f"{side}_shoulder", f"{side}_hip", f"{side}_ankle"]):
                lean = hip_balance_lean_value(f, side)
        except Exception:  # noqa: BLE001
            lean = None
        leans.append(lean)

    load_t = next((f["time_sec"] for f in frames if f["frame"] == load_frame), None)
    release_t = next((f["time_sec"] for f in frames if f["frame"] == release_frame), None)

    fig, axes = plt.subplots(4, 1, figsize=(11, 12), sharex=True)
    series = [
        (axes[0], elbows, "Elbow angle (°)", "tab:blue"),
        (axes[1], wrists, "Wrist angle (°)", "tab:orange"),
        (axes[2], knees, "Knee angle (°)", "tab:green"),
        (axes[3], leans, "Hip lean (°)", "tab:red"),
    ]
    for ax, values, title, color in series:
        xs = [t for t, v in zip(times, values) if v is not None]
        ys = [v for v in values if v is not None]
        ax.plot(xs, ys, color=color, linewidth=1.5)
        ax.set_ylabel(title)
        ax.grid(True, alpha=0.3)
        if load_t is not None:
            ax.axvline(load_t, color="cyan", linestyle="--", linewidth=1.5, label="load")
        if release_t is not None:
            ax.axvline(release_t, color="magenta", linestyle="--", linewidth=1.5, label="release")
        ax.legend(loc="upper right", fontsize=8)

    axes[-1].set_xlabel("time (s)")
    fig.suptitle(f"Shot metrics ({side} side) — load/release highlighted", fontsize=13)
    fig.tight_layout()
    path = output_dir / "metric_timeseries.png"
    fig.savefig(path, dpi=140)
    plt.close(fig)
    print(f"Saved metric plots: {path}")
    return str(path)


def run_diagnostics(
    data: dict,
    side: Optional[str] = None,
    hold_seconds: float = 0.5,
    video_path: Optional[str] = None,
    output_dir: Optional[str | Path] = None,
    score_result: Optional[dict] = None,
) -> dict[str, Any]:
    """
    Print full calibration diagnostics and optionally save plots/frame images.
    Returns a JSON-serializable diagnostic dict (also written to disk if output_dir set).
    """
    resolved_side = get_side(data, side)
    if score_result is None:
        score_result = score_single_shot(data, resolved_side, hold_seconds=hold_seconds)

    diag = collect_metric_rows(data, resolved_side, hold_seconds=hold_seconds)
    rows = diag["rows"]

    out_dir = Path(output_dir) if output_dir else None
    if out_dir is not None:
        out_dir.mkdir(parents=True, exist_ok=True)

    print("\n" + "=" * 60)
    print("SHOT SCORER v4 — CALIBRATION DIAGNOSTICS (no scoring changes)")
    print("=" * 60)
    print(f"Source frames: {len(data.get('frames') or [])}")
    print(f"Shooting side: {resolved_side}")
    print(f"Camera view:   {score_result.get('camera_view')}")
    print(f"Confidence:    {score_result.get('confidence')}")
    print(f"Metrics:       {score_result.get('metrics_computed')}")
    print(f"Unreliable:    {score_result.get('unreliable_metrics')}")

    _print_raw_values(diag["raw"])
    _print_load_release(diag)
    _print_deductions(rows)
    _print_comparison_table(rows)
    _print_section_breakdown(score_result)
    _print_threshold_warning(rows)

    artifacts: dict[str, Any] = {}
    if out_dir is not None:
        artifacts.update(
            _save_phase_frames(
                video_path,
                diag["load_frame"],
                diag["release_frame"],
                out_dir,
                diag["frames"],
            )
        )
        artifacts["plot"] = _save_metric_plots(
            diag["frames"],
            resolved_side,
            diag["load_frame"],
            diag["release_frame"],
            out_dir,
        )

    payload = {
        "shooting_side": resolved_side,
        "overall_score": score_result.get("overall_score"),
        "confidence": score_result.get("confidence"),
        "camera_view": score_result.get("camera_view"),
        "load_frame": diag["load_frame"],
        "release_frame": diag["release_frame"],
        "raw": diag["raw"],
        "true_min_knee": (
            {
                "frame": diag["true_min_knee"][0],
                "time_sec": diag["true_min_knee"][1],
                "knee_angle": diag["true_min_knee"][2],
            }
            if diag.get("true_min_knee")
            else None
        ),
        "metrics": rows,
        "sections": score_result.get("sections"),
        "artifacts": artifacts,
    }

    if out_dir is not None:
        json_path = out_dir / "score_diagnostics.json"
        json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(f"\nWrote diagnostics JSON: {json_path}")

    print("\n" + "=" * 60)
    print("END DIAGNOSTICS")
    print("=" * 60 + "\n")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Calibration diagnostics for Shot Scorer v4 (no scoring changes)."
    )
    parser.add_argument("input", help="shot_angles.json from shot_pose_extractor")
    parser.add_argument("--side", choices=["left", "right"], default=None)
    parser.add_argument("--video", default=None, help="Source video for saving load/release frames")
    parser.add_argument("--output-dir", default="score_diagnostics")
    parser.add_argument("--hold-seconds", type=float, default=0.5)
    args = parser.parse_args()

    with open(args.input, encoding="utf-8") as f:
        data = json.load(f)

    run_diagnostics(
        data,
        side=args.side,
        hold_seconds=args.hold_seconds,
        video_path=args.video,
        output_dir=args.output_dir,
    )


if __name__ == "__main__":
    main()
