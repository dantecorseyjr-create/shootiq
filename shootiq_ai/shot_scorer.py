"""
Shot Scorer v4 — Structured around the app's 7 grading sections:
Feet & Stance, Knee Bend, Ball Position, Elbow Alignment, Shooting Motion,
Follow Through, Balance.

Each section has a point weight (summing to 100) and one or more
underlying measurements. This keeps everything from v3 (confidence
filtering, velocity-based release detection, missing-data-safe scoring)
but reorganizes the output to match the app's actual UI sections instead
of raw internal metric names.

IMPORTANT CAVEAT — BALL POSITION:
There is no ball-tracking (no YOLO/object detector) in this pipeline yet
— only body pose. "Ball position" here is a PROXY: it measures where the
shooting hand (wrist/index finger) sits relative to the head at the set
point, since the ball rests in the hand. This is a reasonable stand-in
but is not the same as tracking the actual ball. Flagged in the output
under each shot's "notes" field so the app can show that caveat to users
if desired.

INPUT:
    shot_angles.json — output of shot_pose_extractor.py (must include the
    "nose" landmark — re-run extraction if using an older JSON file that
    predates this landmark).

OUTPUT:
    shot_score.json with:
      - overall_score (0-100, or null if confidence too low)
      - confidence (0-100)
      - sections: { feet_stance, knee_bend, ball_position, elbow_alignment,
        shooting_motion, follow_through, balance } each with score/max/issues
      - strengths, improvements (coaching-style, frame-referenced)
      - overlay_frames (landmarks + joint_status, for Flutter skeleton overlay)

USAGE:
    python shot_scorer.py shot_angles.json --output shot_score.json
"""

import argparse
import json
import numpy as np

VISIBILITY_THRESHOLD = 0.65
MIN_CONFIDENCE_FOR_SCORE = 60
MIN_SHOULDER_WIDTH_3D = 0.04  # normalized units; below this, shoulder-width-based
                              # metrics are unreliable regardless of camera angle

# ---------------------------------------------------------------------------
# SECTION DEFINITIONS — maps directly to the app's 7 grading categories.
# Each section has one or more underlying metrics; metric points must sum
# to the section's max_points.
# ---------------------------------------------------------------------------
SECTIONS = {
    "feet_stance": {
        "label": "Feet & Stance",
        "max_points": 10,
        "metrics": ["foot_stance_width"],
    },
    "knee_bend": {
        "label": "Knee Bend",
        "max_points": 15,
        "metrics": ["knee_bend_at_load"],
    },
    "ball_position": {
        "label": "Ball Position",
        "max_points": 15,
        "metrics": ["ball_position_height", "ball_position_centering"],
    },
    "elbow_alignment": {
        "label": "Elbow Alignment",
        "max_points": 20,
        "metrics": ["elbow_angle_at_set_point", "elbow_flare"],
    },
    "shooting_motion": {
        "label": "Shooting Motion",
        "max_points": 20,
        "metrics": ["wrist_snap_range", "release_extension"],
    },
    "follow_through": {
        "label": "Follow Through",
        "max_points": 10,
        "metrics": ["follow_through_drift"],
    },
    "balance": {
        "label": "Balance",
        "max_points": 10,
        "metrics": ["hip_balance_lean"],
    },
}

TOLERANCE_BANDS = {
    "foot_stance_width": {"low": 0.85, "high": 1.35, "max_deduction": 10},
    "knee_bend_at_load": {"low": 100, "high": 145, "max_deduction": 15},
    "ball_position_height": {"low": -0.35, "high": 0.10, "max_deduction": 8},
    # normalized (wrist.y - nose.y) / shoulder_width at set point. Negative =
    # wrist above nose (typical set point height). Band allows the ball to
    # sit from well above the head down to roughly nose level.
    "ball_position_centering": {"low": 0.0, "high": 0.35, "max_deduction": 7},
    # horizontal offset of wrist from the shooting-shoulder, normalized by
    # shoulder width. Low = ball held centered/in-line, not off to the side.
    "elbow_angle_at_set_point": {"low": 75, "high": 115, "max_deduction": 8},
    "elbow_flare": {"low": 0.0, "high": 0.14, "max_deduction": 12},
    "wrist_snap_range": {"low": 40, "high": 90, "max_deduction": 10},
    "release_extension": {"low": 160, "high": 180, "max_deduction": 10},
    "follow_through_drift": {"low": 0, "high": 10, "max_deduction": 10},
    "hip_balance_lean": {"low": 0.0, "high": 10.0, "max_deduction": 10},
}

COACHING_TEXT = {
    "foot_stance_width": {
        "good": "Foot stance width is solid and balanced.",
        "bad": "Foot stance is {direction} shoulder width.",
        "fix": "Set feet at roughly shoulder width for a stable, repeatable base.",
    },
    "knee_bend_at_load": {
        "good": "Good knee bend depth for power generation.",
        "bad": "Knee bend at the load phase is {direction}.",
        "fix": "Aim for a consistent, moderate knee bend — not too shallow, not overly deep.",
    },
    "ball_position_height": {
        "good": "Ball held at a strong, consistent height at the set point.",
        "bad": "Ball position height at the set point is {direction} the typical zone.",
        "fix": "Bring the ball up to around forehead height at the set point before rising into the shot.",
    },
    "ball_position_centering": {
        "good": "Ball is held centered and in line with the shooting shoulder.",
        "bad": "Ball position drifts {direction} center at the set point.",
        "fix": "Keep the ball centered over the shooting shoulder rather than off to the side.",
    },
    "elbow_angle_at_set_point": {
        "good": "Elbow angle at the set point is well within range.",
        "bad": "Elbow angle at the set point is {direction}.",
        "fix": "Aim for the forearm roughly vertical at the set point, elbow near a right angle.",
    },
    "elbow_flare": {
        "good": "Elbow stayed tucked in line with the shot the whole way up.",
        "bad": "Elbow flared out to the side during the shot.",
        "fix": "Keep the elbow tucked directly under the ball rather than winging outward.",
    },
    "wrist_snap_range": {
        "good": "Good wrist snap from set point through release.",
        "bad": "Wrist snap range is {direction}.",
        "fix": "Let the wrist cock back at the set point and snap fully forward through release.",
    },
    "release_extension": {
        "good": "Full arm extension at release.",
        "bad": "Arm isn't reaching full extension at release ({direction}).",
        "fix": "Extend the shooting arm fully at release instead of releasing early.",
    },
    "follow_through_drift": {
        "good": "Follow-through was held steady after release.",
        "bad": "Arm position drifted after release instead of holding the follow-through.",
        "fix": "Hold the follow-through pose until the ball reaches the rim.",
    },
    "hip_balance_lean": {
        "good": "Good balance through the shot — minimal lean.",
        "bad": "Noticeable lean/balance issue at release.",
        "fix": "Keep the torso stacked over the base rather than leaning during the shot.",
    },
}

def band_score(value, band):
    low, high, max_ded = band["low"], band["high"], band["max_deduction"]
    if low <= value <= high:
        return 0.0, "within range"
    if value < low:
        overshoot, span, direction = low - value, max(high - low, 1e-6), "below range"
    else:
        overshoot, span, direction = value - high, max(high - low, 1e-6), "above range"
    return round(min(max_ded, (overshoot / span) * max_ded * 2), 2), direction

def get_side(data, requested=None):
    if requested:
        return requested
    frames = data["frames"]
    left_vis, right_vis = [], []
    for f in frames:
        lm = f.get("landmarks", {})
        if "left_wrist" in lm:
            left_vis.append(lm["left_wrist"]["visibility"])
        if "right_wrist" in lm:
            right_vis.append(lm["right_wrist"]["visibility"])
    return "right" if (np.mean(right_vis) if right_vis else 0) >= (np.mean(left_vis) if left_vis else 0) else "left"

def joints_visible(frame, joint_names, threshold=VISIBILITY_THRESHOLD):
    lm = frame.get("landmarks", {})
    return all(name in lm and lm[name]["visibility"] >= threshold for name in joint_names)

def _p3(lm, name):
    """3D point (x, y, z) for a landmark — using depth avoids the shoulder-width
    collapse that happens when a shot is filmed from the side (very common for
    shot-form video) instead of head-on."""
    j = lm[name]
    return np.array([j["x"], j["y"], j["z"]])

def safe_shoulder_width(lm):
    """
    Returns (width, reliable). width is the 3D shoulder distance. reliable is
    False if the width is below MIN_SHOULDER_WIDTH_3D, meaning shoulder-width
    normalized metrics (flare, stance, ball position) should not be trusted
    for this frame even after the 3D fix — e.g. a shooter facing directly
    away from or toward the camera, or a landmark-detection glitch.
    """
    ls = _p3(lm, "left_shoulder")
    rs = _p3(lm, "right_shoulder")
    width = float(np.linalg.norm(ls - rs))
    return width, width >= MIN_SHOULDER_WIDTH_3D

MISTAKE_PAD_SECONDS = 0.15  # default padding around a single-instant mistake, in real seconds

def mistake_window(frames, metric, deduction_frame, load_frame_num, release_frame_num, hold_seconds):
    """
    Returns (start_frame, start_time, end_frame, end_time) for a flagged
    mistake, so playback can clip to just the relevant segment instead of
    a single frame. Metrics that were measured across a natural window
    (elbow flare over load->release, wrist snap over load->release,
    follow-through drift over release->release+hold) use that real window.
    Single-instant metrics (measured at one frame) get a fixed time pad on
    each side instead.
    """
    frame_lookup = {f["frame"]: f for f in frames}
    times = [f["time_sec"] for f in frames]
    clip_start_time, clip_end_time = (min(times), max(times)) if times else (0, 0)

    if metric in ("elbow_flare", "wrist_snap_range") and load_frame_num is not None and release_frame_num is not None:
        start_frame, end_frame = load_frame_num, release_frame_num
    elif metric == "follow_through_drift" and release_frame_num is not None:
        release_time = frame_lookup.get(release_frame_num, {}).get("time_sec")
        start_frame = release_frame_num
        end_frame = min(
            (f["frame"] for f in frames if release_time is not None and f["time_sec"] <= release_time + hold_seconds),
            default=release_frame_num, key=lambda fn: -fn
        ) if release_time is not None else release_frame_num
    else:
        # single-instant metric: pad by a fixed time window around the flagged frame
        center_time = frame_lookup.get(deduction_frame, {}).get("time_sec")
        if center_time is None:
            return deduction_frame, None, deduction_frame, None
        target_start = max(clip_start_time, center_time - MISTAKE_PAD_SECONDS)
        target_end = min(clip_end_time, center_time + MISTAKE_PAD_SECONDS)
        start_frame = min(frames, key=lambda f: abs(f["time_sec"] - target_start))["frame"]
        end_frame = min(frames, key=lambda f: abs(f["time_sec"] - target_end))["frame"]

    start_time = frame_lookup.get(start_frame, {}).get("time_sec")
    end_time = frame_lookup.get(end_frame, {}).get("time_sec")
    return start_frame, start_time, end_frame, end_time

def detect_camera_view(lm):
    """
    Classifies the camera angle relative to the shooter using the ratio of
    horizontal (x) to depth (z) separation between the shoulders:
      - mostly x separation, minimal z  -> "front"
      - mostly z separation, minimal x  -> "side"
      - comparable x and z              -> "45_degree"
      - shoulders not both visible      -> "unknown"
    This does not fix accuracy on its own — it's a diagnostic flag so low
    scores can be traced back to camera angle rather than assumed to be bad
    form.
    """
    try:
        ls = _p3(lm, "left_shoulder")
        rs = _p3(lm, "right_shoulder")
    except KeyError:
        return "unknown"
    dx = abs(ls[0] - rs[0])
    dz = abs(ls[2] - rs[2])
    if dx + dz < 1e-6:
        return "unknown"
    angle_deg = np.degrees(np.arctan2(dz, dx))  # 0 = pure front, 90 = pure side
    if angle_deg < 25:
        return "front"
    elif angle_deg > 65:
        return "side"
    else:
        return "45_degree"

def elbow_flare_value(frame, side):
    lm = frame["landmarks"]
    shoulder_width, reliable = safe_shoulder_width(lm)
    if not reliable:
        return None
    shoulder = _p3(lm, f"{side}_shoulder")
    elbow = _p3(lm, f"{side}_elbow")
    wrist = _p3(lm, f"{side}_wrist")
    line_vec = wrist - shoulder
    line_unit = line_vec / (np.linalg.norm(line_vec) + 1e-9)
    proj_point = shoulder + np.dot(elbow - shoulder, line_unit) * line_unit
    return float(np.linalg.norm(elbow - proj_point) / shoulder_width)

def foot_stance_width_value(frame):
    lm = frame["landmarks"]
    shoulder_width, reliable = safe_shoulder_width(lm)
    if not reliable:
        return None
    la = _p3(lm, "left_ankle")
    ra = _p3(lm, "right_ankle")
    return float(np.linalg.norm(la - ra) / shoulder_width)

def hip_balance_lean_value(frame, side):
    lm = frame["landmarks"]
    shoulder = _p3(lm, f"{side}_shoulder")
    ankle = _p3(lm, f"{side}_ankle")
    body_vec = shoulder - ankle
    vertical_vec = np.array([0.0, -1.0, 0.0])
    cos_angle = np.clip(np.dot(body_vec, vertical_vec) / (np.linalg.norm(body_vec) * np.linalg.norm(vertical_vec) + 1e-9), -1.0, 1.0)
    return float(np.degrees(np.arccos(cos_angle)))

def ball_position_height_value(frame, side):
    """(wrist.y - nose.y) / shoulder_width — proxy for ball height at set point.
    Uses 3D shoulder width so this doesn't blow up on side-angle footage."""
    lm = frame["landmarks"]
    shoulder_width, reliable = safe_shoulder_width(lm)
    if not reliable:
        return None
    wrist_y = lm[f"{side}_wrist"]["y"]
    nose_y = lm["nose"]["y"]
    return float((wrist_y - nose_y) / shoulder_width)

def ball_position_centering_value(frame, side):
    """Horizontal offset of wrist from shooting shoulder, normalized by 3D shoulder width."""
    lm = frame["landmarks"]
    shoulder_width, reliable = safe_shoulder_width(lm)
    if not reliable:
        return None
    wrist_x = lm[f"{side}_wrist"]["x"]
    shoulder_x = lm[f"{side}_shoulder"]["x"]
    return float(abs(wrist_x - shoulder_x) / shoulder_width)

def find_wrist_ascent_start_frame(frames, side, run_seconds=0.1, velocity_threshold=-0.06,
                                   min_range_fraction=0.12):
    """
    Finds the first frame where the shooting wrist begins a SUSTAINED upward
    rise (velocity below threshold for a run of `run_seconds`, converted to
    frames using each clip's own fps — NOT a hardcoded frame count, so this
    works the same on 24fps, 30fps, 60fps, or any other frame rate).

    Velocity is computed against actual time_sec gaps between frames (not an
    assumed uniform 1-frame spacing), so it's also correct if frames were
    dropped or the source video has variable frame timing. The threshold is
    in normalized-y-units-per-second, so it reflects real motion speed rather
    than an arbitrary per-frame delta — this means a genuinely quick release
    (fast wrist rise) is still detected correctly, not penalized for being
    fast.

    A per-frame velocity threshold alone is fooled by small, slow hand drift
    (e.g. dribbling/adjusting before the shot even starts) — over a short
    enough run, that drift's velocity can dip below the threshold by noise
    alone even though it covers almost no real distance. So a candidate run
    must ALSO cover at least `min_range_fraction` of the wrist's total
    observed range of motion in the clip — the real shot rise dominates that
    range, incidental pre-shot drift doesn't. This scales with the clip's own
    framing/zoom instead of a fixed absolute displacement.

    Used to cap the load-frame search so a deep knee bend later in the clip
    — e.g. a landing squat after the shot — can't be mistaken for the
    pre-shot load. Returns None if no clear sustained rise is found (falls
    back to no cap).
    """
    required = [f"{side}_wrist"]
    candidates = [(f["frame"], f["time_sec"], f["landmarks"][f"{side}_wrist"]["y"]) for f in frames
                  if f.get("landmarks") and joints_visible(f, required)]
    if len(candidates) < 3:
        return None

    frame_nums = [c[0] for c in candidates]
    times = np.array([c[1] for c in candidates])
    ys = np.array([c[2] for c in candidates])

    # estimate this clip's actual fps from its own timestamps, so run_seconds
    # converts to a sane frame count regardless of source frame rate
    dt = np.median(np.diff(times)) if len(times) > 1 else (1 / 30)
    dt = dt if dt > 1e-6 else (1 / 30)
    run_len = max(2, round(run_seconds / dt))

    velocity = np.gradient(ys, times)  # y-units per second; negative = moving up
    y_range = ys.max() - ys.min()
    min_displacement = y_range * min_range_fraction if y_range > 1e-6 else 0.0
    for i in range(len(velocity) - run_len):
        if np.all(velocity[i:i + run_len] < velocity_threshold):
            net_displacement = ys[i] - ys[i + run_len]
            if net_displacement >= min_displacement:
                return frame_nums[i]
    return None

def find_load_frame(frames, side, buffer_seconds=0.1, lookback_seconds=0.3):
    required = [f"{side}_hip", f"{side}_knee", f"{side}_ankle"]

    # cap the search to a window immediately around the wrist's real upward
    # rise, so neither a deeper dip later in the clip (e.g. landing after the
    # shot) NOR an earlier, disconnected crouch (e.g. a dribble/adjustment
    # well before the shot even starts) can be picked over the actual
    # pre-shot load. Both bounds are in real seconds (not a frame count) so
    # this stays correct across different frame rates and shot speeds.
    ascent_start = find_wrist_ascent_start_frame(frames, side)
    if ascent_start is None:
        search_pool = frames
    else:
        ascent_time = next((f["time_sec"] for f in frames if f["frame"] == ascent_start), None)
        if ascent_time is None:
            search_pool = frames
        else:
            cutoff_time = ascent_time + buffer_seconds
            floor_time = ascent_time - lookback_seconds
            search_pool = [f for f in frames if floor_time <= f["time_sec"] <= cutoff_time]
    if not search_pool:
        search_pool = frames

    candidates = [(f["frame"], f["angles"][f"{side}_knee"]) for f in search_pool
                  if "angles" in f and f"{side}_knee" in f["angles"] and joints_visible(f, required)]
    if not candidates:
        # fall back to the unrestricted search if the capped window had no usable frames
        candidates = [(f["frame"], f["angles"][f"{side}_knee"]) for f in frames
                      if "angles" in f and f"{side}_knee" in f["angles"] and joints_visible(f, required)]
    return min(candidates, key=lambda c: c[1])[0] if candidates else None

def find_release_frame_velocity(frames, side, load_frame_num):
    if load_frame_num is None:
        return None
    required = [f"{side}_shoulder", f"{side}_elbow", f"{side}_wrist"]
    post_load = [f for f in frames if f["frame"] >= load_frame_num and "angles" in f
                 and f"{side}_elbow" in f["angles"] and f"{side}_wrist" in f["angles"] and joints_visible(f, required)]
    if len(post_load) < 3:
        candidates = [(f["frame"], f["angles"][f"{side}_wrist"]) for f in post_load]
        return max(candidates, key=lambda c: c[1])[0] if candidates else None

    frame_nums = [f["frame"] for f in post_load]
    times = np.array([f["time_sec"] for f in post_load])
    # gradient against real timestamps, not an assumed uniform frame gap —
    # keeps this correct at 24fps, 30fps, 60fps, or variable frame timing,
    # and doesn't penalize a genuinely fast release
    elbow_v = np.gradient(np.array([f["angles"][f"{side}_elbow"] for f in post_load]), times)
    wrist_v = np.gradient(np.array([f["angles"][f"{side}_wrist"] for f in post_load]), times)

    def norm(a):
        rng = a.max() - a.min()
        return (a - a.min()) / rng if rng > 1e-6 else np.zeros_like(a)

    combined = norm(np.abs(elbow_v)) + norm(np.abs(wrist_v))
    return frame_nums[int(np.argmax(combined))]

# metric_name -> (required_joints_fn(side), value_fn(frame, side), reference_frame: "load" | "release")
METRIC_DEFS = {
    "foot_stance_width": (lambda side: ["left_ankle", "right_ankle", "left_shoulder", "right_shoulder"],
                          lambda frame, side: foot_stance_width_value(frame), "load"),
    "knee_bend_at_load": (lambda side: [f"{side}_hip", f"{side}_knee", f"{side}_ankle"],
                          lambda frame, side: frame["angles"][f"{side}_knee"], "load"),
    "ball_position_height": (lambda side: [f"{side}_wrist", "nose", "left_shoulder", "right_shoulder"],
                             ball_position_height_value, "load"),
    "ball_position_centering": (lambda side: [f"{side}_wrist", f"{side}_shoulder", "left_shoulder", "right_shoulder"],
                                ball_position_centering_value, "load"),
    "elbow_angle_at_set_point": (lambda side: [f"{side}_shoulder", f"{side}_elbow", f"{side}_wrist"],
                                 lambda frame, side: frame["angles"][f"{side}_elbow"], "load"),
    "release_extension": (lambda side: [f"{side}_shoulder", f"{side}_elbow", f"{side}_wrist"],
                          lambda frame, side: frame["angles"][f"{side}_elbow"], "release"),
}

def compute_tempo_metrics(frames, side, load_frame_num, release_frame_num):
    """
    Supplementary timing data — NOT part of the 7-section score, since tempo
    isn't one of the app's scoring categories. All durations are real
    seconds (via time_sec), so this is correct at any frame rate and for a
    genuinely fast release.

    dip_start_frame: approximated as the frame with the highest wrist
    position (minimum y) in the window before the load frame — i.e. where
    the shooter starts descending into the load. This is a proxy, not a
    biomechanically validated dip-onset detector.
    """
    frame_lookup = {f["frame"]: f for f in frames}
    result = {
        "dip_start_frame": None, "dip_start_time_sec": None,
        "load_frame": load_frame_num,
        "load_time_sec": frame_lookup.get(load_frame_num, {}).get("time_sec"),
        "release_frame": release_frame_num,
        "release_time_sec": frame_lookup.get(release_frame_num, {}).get("time_sec"),
        "dip_duration_sec": None, "rise_duration_sec": None, "total_duration_sec": None,
        "release_wrist_angular_velocity_deg_per_sec": None,
    }

    if load_frame_num is not None:
        required = [f"{side}_wrist"]
        pre_load = [f for f in frames if f["frame"] <= load_frame_num
                    and f.get("landmarks") and joints_visible(f, required)]
        if pre_load:
            dip_start = min(pre_load, key=lambda f: f["landmarks"][f"{side}_wrist"]["y"])
            result["dip_start_frame"] = dip_start["frame"]
            result["dip_start_time_sec"] = dip_start["time_sec"]

    if result["dip_start_time_sec"] is not None and result["load_time_sec"] is not None:
        result["dip_duration_sec"] = round(result["load_time_sec"] - result["dip_start_time_sec"], 3)
    if result["load_time_sec"] is not None and result["release_time_sec"] is not None:
        result["rise_duration_sec"] = round(result["release_time_sec"] - result["load_time_sec"], 3)
    if result["dip_start_time_sec"] is not None and result["release_time_sec"] is not None:
        result["total_duration_sec"] = round(result["release_time_sec"] - result["dip_start_time_sec"], 3)

    # release wrist angular velocity: local slope of wrist angle around the release frame
    if release_frame_num is not None:
        required = [f"{side}_wrist"]
        window = [f for f in frames if abs(f["frame"] - release_frame_num) <= 3
                  and "angles" in f and f"{side}_wrist" in f["angles"] and joints_visible(f, required)]
        window.sort(key=lambda f: f["frame"])
        if len(window) >= 2:
            times = np.array([f["time_sec"] for f in window])
            angles = np.array([f["angles"][f"{side}_wrist"] for f in window])
            velocities = np.gradient(angles, times)
            idx = min(range(len(window)), key=lambda i: abs(window[i]["frame"] - release_frame_num))
            result["release_wrist_angular_velocity_deg_per_sec"] = round(float(velocities[idx]), 1)

    return result

def compute_rotation_metrics(frames, side, load_frame_num, release_frame_num):
    """
    Supplementary body-rotation data — NOT part of the 7-section score.
    Measures how much the shoulder and hip lines rotate (in the horizontal
    x/z plane) between load and release, using 3D coordinates so this isn't
    distorted by camera angle the way a flat x/y measurement would be.
    A positive value means the torso opened up during the shot; near-zero
    means the shooter stayed square throughout.
    """
    frame_lookup = {f["frame"]: f for f in frames}
    result = {
        "shoulder_rotation_deg": None,
        "hip_rotation_deg": None,
        "note": "Rotation is measured in the horizontal (x/z) plane using 3D landmarks. "
                "This is diagnostic data, not part of the 7-section score.",
    }
    if load_frame_num is None or release_frame_num is None:
        return result

    def line_angle_xz(lm, left_name, right_name):
        l = lm[left_name]
        r = lm[right_name]
        return np.degrees(np.arctan2(r["z"] - l["z"], r["x"] - l["x"]))

    load_lm = frame_lookup.get(load_frame_num, {}).get("landmarks", {})
    release_lm = frame_lookup.get(release_frame_num, {}).get("landmarks", {})

    if load_lm and release_lm and "left_shoulder" in load_lm and "right_shoulder" in load_lm \
            and "left_shoulder" in release_lm and "right_shoulder" in release_lm:
        a1 = line_angle_xz(load_lm, "left_shoulder", "right_shoulder")
        a2 = line_angle_xz(release_lm, "left_shoulder", "right_shoulder")
        delta = ((a2 - a1 + 180) % 360) - 180  # wrap to [-180, 180]
        result["shoulder_rotation_deg"] = round(float(delta), 1)

    if load_lm and release_lm and "left_hip" in load_lm and "right_hip" in load_lm \
            and "left_hip" in release_lm and "right_hip" in release_lm:
        a1 = line_angle_xz(load_lm, "left_hip", "right_hip")
        a2 = line_angle_xz(release_lm, "left_hip", "right_hip")
        delta = ((a2 - a1 + 180) % 360) - 180
        result["hip_rotation_deg"] = round(float(delta), 1)

    return result

def score_single_shot(data, side, hold_seconds=0.5):
    """
    hold_seconds: how long after release the follow-through should be held,
    in real seconds (not frames), so this behaves the same at any frame rate.
    """
    frames = data["frames"]
    frame_lookup = {f["frame"]: f for f in frames}
    load_frame_num = find_load_frame(frames, side)
    release_frame_num = find_release_frame_velocity(frames, side, load_frame_num)

    metric_scores = {}   # metric_name -> points earned (or None)
    metric_deductions = []
    unreliable_metrics = []  # metrics skipped due to low shoulder-width confidence (not missing pose data)
    computed_metrics, total_metrics = 0, 0

    def max_points_for(metric):
        for sec in SECTIONS.values():
            if metric in sec["metrics"]:
                return sec["max_points"] / len(sec["metrics"])
        return 0

    # simple load/release metrics
    for metric, (req_fn, value_fn, ref) in METRIC_DEFS.items():
        total_metrics += 1
        ref_frame_num = load_frame_num if ref == "load" else release_frame_num
        if ref_frame_num is None or ref_frame_num not in frame_lookup:
            metric_scores[metric] = None
            continue
        frame = frame_lookup[ref_frame_num]
        if not joints_visible(frame, req_fn(side)):
            metric_scores[metric] = None
            continue
        value = value_fn(frame, side)
        if value is None:
            metric_scores[metric] = None
            unreliable_metrics.append(metric)
            continue
        ded, verdict = band_score(value, TOLERANCE_BANDS[metric])
        pts = max_points_for(metric)
        metric_scores[metric] = round(pts - ded, 2)
        computed_metrics += 1
        if ded > 0:
            metric_deductions.append({"metric": metric, "frame": ref_frame_num,
                                       "value": round(value, 4) if isinstance(value, float) else value,
                                       "verdict": verdict, "deduction": ded})

    # elbow_flare: needs a window scan (load -> release), not a single frame
    total_metrics += 1
    if load_frame_num is not None and release_frame_num is not None:
        req = [f"{side}_shoulder", f"{side}_elbow", f"{side}_wrist", "left_shoulder", "right_shoulder"]
        window = [f for f in frames if load_frame_num <= f["frame"] <= release_frame_num]
        raw_flares = [(f["frame"], elbow_flare_value(f, side)) for f in window if joints_visible(f, req)]
        flares = [(fr, v) for fr, v in raw_flares if v is not None]
        if not flares and raw_flares:
            # every frame in the window had unreliable shoulder width
            metric_scores["elbow_flare"] = None
            unreliable_metrics.append("elbow_flare")
        elif flares:
            worst_frame, worst_val = max(flares, key=lambda x: x[1])
            ded, verdict = band_score(worst_val, TOLERANCE_BANDS["elbow_flare"])
            pts = max_points_for("elbow_flare")
            metric_scores["elbow_flare"] = round(pts - ded, 2)
            computed_metrics += 1
            if ded > 0:
                metric_deductions.append({"metric": "elbow_flare", "frame": worst_frame,
                                           "value": round(worst_val, 4), "verdict": verdict, "deduction": ded})
        else:
            metric_scores["elbow_flare"] = None
    else:
        metric_scores["elbow_flare"] = None

    # wrist_snap_range: needs both load and release frames
    total_metrics += 1
    if load_frame_num is not None and release_frame_num is not None:
        lf, rf = frame_lookup.get(load_frame_num), frame_lookup.get(release_frame_num)
        req = [f"{side}_elbow", f"{side}_wrist", f"{side}_index"]
        if lf and rf and joints_visible(lf, req) and joints_visible(rf, req):
            snap_range = abs(rf["angles"][f"{side}_wrist"] - lf["angles"][f"{side}_wrist"])
            ded, verdict = band_score(snap_range, TOLERANCE_BANDS["wrist_snap_range"])
            pts = max_points_for("wrist_snap_range")
            metric_scores["wrist_snap_range"] = round(pts - ded, 2)
            computed_metrics += 1
            if ded > 0:
                metric_deductions.append({"metric": "wrist_snap_range", "frame": release_frame_num,
                                           "value": round(snap_range, 2), "verdict": verdict, "deduction": ded})
        else:
            metric_scores["wrist_snap_range"] = None
    else:
        metric_scores["wrist_snap_range"] = None

    # follow_through_drift: needs a post-release window
    total_metrics += 1
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
            ded, verdict = band_score(drift, TOLERANCE_BANDS["follow_through_drift"])
            pts = max_points_for("follow_through_drift")
            metric_scores["follow_through_drift"] = round(pts - ded, 2)
            computed_metrics += 1
            if ded > 0:
                metric_deductions.append({"metric": "follow_through_drift", "frame": release_frame_num,
                                           "value": round(drift, 2), "verdict": verdict, "deduction": ded})
        else:
            metric_scores["follow_through_drift"] = None
    else:
        metric_scores["follow_through_drift"] = None

    # hip_balance_lean: at release
    total_metrics += 1
    if release_frame_num is not None:
        req = [f"{side}_shoulder", f"{side}_hip", f"{side}_ankle"]
        rf = frame_lookup[release_frame_num]
        if joints_visible(rf, req):
            lean = hip_balance_lean_value(rf, side)
            ded, verdict = band_score(lean, TOLERANCE_BANDS["hip_balance_lean"])
            pts = max_points_for("hip_balance_lean")
            metric_scores["hip_balance_lean"] = round(pts - ded, 2)
            computed_metrics += 1
            if ded > 0:
                metric_deductions.append({"metric": "hip_balance_lean", "frame": release_frame_num,
                                           "value": round(lean, 2), "verdict": verdict, "deduction": ded})
        else:
            metric_scores["hip_balance_lean"] = None
    else:
        metric_scores["hip_balance_lean"] = None

    # --- roll metrics up into the 7 app sections ---
    sections_out = {}
    for key, sec in SECTIONS.items():
        earned, max_pts, issues, any_computed = 0.0, sec["max_points"], [], False
        for metric in sec["metrics"]:
            score = metric_scores.get(metric)
            if score is not None:
                earned += score
                any_computed = True
            for d in metric_deductions:
                if d["metric"] == metric:
                    text = COACHING_TEXT.get(metric, {})
                    start_f, start_t, end_f, end_t = mistake_window(
                        frames, metric, d["frame"], load_frame_num, release_frame_num, hold_seconds
                    )
                    issues.append({
                        "metric": metric, "frame": d["frame"],
                        "time_sec": frame_lookup[d["frame"]]["time_sec"] if d["frame"] in frame_lookup else None,
                        "start_frame": start_f, "start_time_sec": start_t,
                        "end_frame": end_f, "end_time_sec": end_t,
                        "value": d["value"], "verdict": d["verdict"], "deduction": d["deduction"],
                        "explanation": text.get("bad", "").format(direction=d["verdict"]),
                        "fix": text.get("fix", ""),
                    })
        sections_out[key] = {
            "label": sec["label"],
            "score": round(earned, 1) if any_computed else None,
            "max_points": max_pts,
            "issues": issues,
        }

    computed_sections = [s for s in sections_out.values() if s["score"] is not None]
    confidence = round((computed_metrics / total_metrics) * 100, 1) if total_metrics else 0

    # camera view: classify from the load frame (falls back to release frame,
    # then any frame with visible shoulders) so a single representative
    # reading is used rather than re-classifying every frame
    camera_view = "unknown"
    for probe_frame_num in [load_frame_num, release_frame_num]:
        if probe_frame_num is not None and probe_frame_num in frame_lookup:
            fl = frame_lookup[probe_frame_num].get("landmarks", {})
            if fl:
                camera_view = detect_camera_view(fl)
                if camera_view != "unknown":
                    break
    if camera_view == "unknown":
        for f in frames:
            fl = f.get("landmarks", {})
            if fl:
                v = detect_camera_view(fl)
                if v != "unknown":
                    camera_view = v
                    break

    if not computed_sections:
        overall = None
    else:
        earned_total = sum(s["score"] for s in computed_sections)
        max_total = sum(SECTIONS[k]["max_points"] for k, s in sections_out.items() if s["score"] is not None)
        overall = round((earned_total / max_total) * 100, 1) if max_total else None
        if confidence < MIN_CONFIDENCE_FOR_SCORE:
            overall = None

    # --- strengths ---
    strengths = []
    for metric, score in metric_scores.items():
        if score is None:
            continue
        if not any(d["metric"] == metric for d in metric_deductions):
            text = COACHING_TEXT.get(metric, {})
            if "good" in text:
                strengths.append(text["good"])

    improvements = []
    section_counters: dict[str, int] = {}
    for key, sec in sections_out.items():
        for issue in sec["issues"]:
            band = TOLERANCE_BANDS[issue["metric"]]
            severity = "high" if issue["deduction"] > band["max_deduction"] * 0.6 else (
                "medium" if issue["deduction"] > band["max_deduction"] * 0.3 else "low")
            # Deterministic id from section key + per-section ordinal (stable
            # across runs for the same issue order within a section).
            section_counters[key] = section_counters.get(key, 0) + 1
            improvement_id = f"{key}_{section_counters[key]:02d}"
            improvements.append({
                "id": improvement_id,
                "section": sec["label"], "issue": issue["metric"].replace("_", " ").title(),
                "frame": issue["frame"], "time_sec": issue["time_sec"],
                "start_frame": issue["start_frame"], "start_time_sec": issue["start_time_sec"],
                "end_frame": issue["end_frame"], "end_time_sec": issue["end_time_sec"],
                "severity": severity,
                "explanation": issue["explanation"], "fix": issue["fix"],
            })
    improvements.sort(key=lambda x: {"high": 0, "medium": 1, "low": 2}[x["severity"]])

    # --- overlay frames (joint_status keyed to the 7 sections' relevant joints) ---
    SECTION_TO_JOINTS = {
        "feet_stance": ["left_ankle", "right_ankle"],
        "knee_bend": [f"{side}_knee", f"{side}_hip", f"{side}_ankle"],
        "ball_position": [f"{side}_wrist", f"{side}_index"],
        "elbow_alignment": [f"{side}_elbow"],
        "shooting_motion": [f"{side}_wrist", f"{side}_elbow"],
        "follow_through": [f"{side}_wrist", f"{side}_elbow"],
        "balance": [f"{side}_hip", f"{side}_shoulder"],
    }
    flagged_frames_by_section = {}
    for key, sec in sections_out.items():
        for issue in sec["issues"]:
            flagged_frames_by_section.setdefault(issue["frame"], []).append(key)

    ISSUE_WINDOW_SECONDS = 0.17  # how long a flagged issue stays highlighted around its frame
    flagged_frame_times = {ff: next((fr["time_sec"] for fr in frames if fr["frame"] == ff), None)
                            for ff in flagged_frames_by_section}
    overlay_frames = []
    for f in frames:
        if "landmarks" not in f or not f["landmarks"]:
            continue
        all_joints = set(j for joints in SECTION_TO_JOINTS.values() for j in joints)
        status = {j: "green" for j in all_joints}
        for flagged_frame, section_keys in flagged_frames_by_section.items():
            flagged_time = flagged_frame_times.get(flagged_frame)
            if flagged_time is not None and abs(flagged_time - f["time_sec"]) <= ISSUE_WINDOW_SECONDS:
                for sk in section_keys:
                    for j in SECTION_TO_JOINTS.get(sk, []):
                        status[j] = "red"
        overlay_frames.append({
            "frame": f["frame"], "time_sec": f["time_sec"], "landmarks": f["landmarks"],
            "is_load_frame": f["frame"] == load_frame_num,
            "is_release_frame": f["frame"] == release_frame_num,
            "joint_status": status,
        })

    tempo = compute_tempo_metrics(frames, side, load_frame_num, release_frame_num)
    rotation = compute_rotation_metrics(frames, side, load_frame_num, release_frame_num)

    return {
        "shooting_side": side,
        "load_frame": load_frame_num,
        "release_frame": release_frame_num,
        "overall_score": overall,
        "confidence": confidence,
        "camera_view": camera_view,
        "metrics_computed": f"{computed_metrics}/{total_metrics}",
        "unreliable_metrics": unreliable_metrics,
        "sections": sections_out,
        "strengths": strengths,
        "improvements": improvements,
        "tempo": tempo,
        "rotation": rotation,
        "overlay_frames": overlay_frames,
        "notes": "ball_position is a proxy based on shooting-hand position relative to "
                 "the head/shoulders, since no ball-tracking model is in this pipeline yet. "
                 "Metrics listed in unreliable_metrics were skipped because shoulder width "
                 "was too small to normalize against reliably, even in 3D — usually caused "
                 "by a camera angle nearly straight-on or straight-behind the shooter. "
                 "tempo and rotation are supplementary diagnostic data, not part of the "
                 "7-section score.",
    }


# Joint highlights + phase keys for Flutter MovementIssue / Results cards.
_SECTION_UI = {
    "feet_stance": {
        "highlight": ["foot", "ankle"],
        "phase": "Setup",
        "phase_key": "setup",
    },
    "knee_bend": {
        "highlight": ["knee", "hip"],
        "phase": "Load",
        "phase_key": "knee_load",
    },
    "ball_position": {
        "highlight": ["wrist", "arm"],
        "phase": "Set Point",
        "phase_key": "set_point",
    },
    "elbow_alignment": {
        "highlight": ["elbow", "forearm"],
        "phase": "Set Point",
        "phase_key": "set_point",
    },
    "shooting_motion": {
        "highlight": ["wrist", "elbow", "arm"],
        "phase": "Release",
        "phase_key": "release",
    },
    "follow_through": {
        "highlight": ["wrist", "elbow", "arm"],
        "phase": "Follow Through",
        "phase_key": "follow_through",
    },
    "balance": {
        "highlight": ["hip", "shoulder", "torso"],
        "phase": "Release",
        "phase_key": "release",
    },
}


def _format_timestamp(seconds) -> str:
    total = int(round(float(seconds or 0)))
    total = max(0, total)
    return f"{total // 60:02d}:{total % 60:02d}"


def _section_percent(score, max_points: float):
    if score is None or not max_points:
        return None
    return int(round(max(0.0, min(100.0, (float(score) / float(max_points)) * 100.0))))


def _status_color(pct):
    if pct is None:
        return "FAIL", "RED"
    if pct >= 80:
        return "PASS", "GREEN"
    if pct >= 60:
        return "WARN", "YELLOW"
    return "FAIL", "RED"


def to_analyze_payload(score_result: dict) -> dict:
    """
    Expand a score_single_shot() result into Flutter-compatible /analyze fields
    while keeping the raw Shot Scorer v4 keys.
    """
    sections = score_result.get("sections") or {}
    improvements = score_result.get("improvements") or []
    strengths = list(score_result.get("strengths") or [])
    confidence = float(score_result.get("confidence") or 0.0)

    biomechanics = []
    metrics = {}
    for key, sec in sections.items():
        label = sec.get("label") or key
        max_pts = float(sec.get("max_points") or 0)
        pct = _section_percent(sec.get("score"), max_pts)
        status, color = _status_color(pct)
        issues = sec.get("issues") or []
        first = issues[0] if issues else {}
        seconds = first.get("time_sec")
        if seconds is None and score_result.get("load_frame") is not None:
            seconds = 0.0
        ui = _SECTION_UI.get(key, {})
        if pct is None:
            issue = "Not enough visible joints to score this section"
            correction = "Retake with your full body visible and good lighting"
            measurement = "insufficient data"
            display_score = 0
        else:
            issue = first.get("explanation") or (
                "Solid mechanics here." if status == "PASS" else f"{label} needs attention."
            )
            correction = first.get("fix") or (
                "Keep repeating this form." if status == "PASS" else "Adjust and try again."
            )
            measurement = f"{sec.get('score')}/{int(max_pts)} pts"
            display_score = pct

        biomechanics.append(
            {
                "category": label,
                "score": display_score,
                "status": status,
                "color": color,
                "issue": issue,
                "correction": correction,
                "measurement": measurement,
                "timestamp": _format_timestamp(seconds),
                "seconds": float(seconds or 0.0),
                "confidence": confidence / 100.0,
                "highlight": list(ui.get("highlight") or []),
                "phase": ui.get("phase"),
                "phase_key": ui.get("phase_key"),
            }
        )

        if key == "feet_stance":
            metrics["feet_stance"] = display_score
            metrics["stance"] = display_score
        elif key == "knee_bend":
            metrics["knee_bend"] = display_score
            metrics["load"] = display_score
        elif key == "ball_position":
            metrics["release_position"] = display_score
        elif key == "elbow_alignment":
            metrics["elbow_alignment"] = display_score
            metrics["set_point"] = display_score
        elif key == "shooting_motion":
            metrics["release_point"] = display_score
            metrics["release"] = display_score
        elif key == "follow_through":
            metrics["follow_through"] = display_score
        elif key == "balance":
            metrics["balance"] = display_score

    issues = [
        item.get("explanation") or item.get("issue") or ""
        for item in improvements
        if (item.get("explanation") or item.get("issue"))
    ]
    recommendations = [
        item.get("fix") or ""
        for item in improvements
        if item.get("fix")
    ]

    overall = score_result.get("overall_score")
    overall_out = int(round(float(overall))) if overall is not None else None

    return {
        **score_result,
        "overall_score": overall_out,
        "biomechanics": biomechanics,
        "breakdown": biomechanics,
        "metrics": metrics,
        "issues": issues,
        "recommendations": recommendations,
        "improvement_summary": (
            recommendations[0]
            if recommendations
            else (issues[0] if issues else "Review your shot mechanics")
        ),
        "scorer": "shot_scorer_v4",
        "step": 6,
    }

def main():
    parser = argparse.ArgumentParser(description="Score a shot into the app's 7 sections.")
    parser.add_argument("inputs", nargs="+")
    parser.add_argument("--side", choices=["left", "right"], default=None)
    parser.add_argument("--output", default="shot_score.json")
    parser.add_argument("--hold-seconds", type=float, default=0.5,
                        help="How long after release to check the follow-through hold, in real seconds")
    args = parser.parse_args()

    all_results = []
    for path in args.inputs:
        with open(path) as f:
            data = json.load(f)
        side = get_side(data, args.side)
        result = score_single_shot(data, side, hold_seconds=args.hold_seconds)
        result["source_file"] = path
        all_results.append(result)

    with open(args.output, "w") as f:
        json.dump({"shots": all_results}, f, indent=2)

    print(f"Written to: {args.output}\n")
    for r in all_results:
        print(f"--- {r['source_file']} ---")
        print(f"Overall: {r['overall_score']} (confidence {r['confidence']}%, metrics {r['metrics_computed']})")
        for key, sec in r["sections"].items():
            print(f"  {sec['label']}: {sec['score']}/{sec['max_points']}")
        if r["improvements"]:
            print("Top issues:")
            for i in r["improvements"][:5]:
                print(f"  [{i['severity']}] {i['section']} — {i['fix']}")
        print()

if __name__ == "__main__":
    main()
