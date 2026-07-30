"""Configurable ideal ranges for phase-scoped shooting biomechanics."""

from __future__ import annotations

# --- Stance: foot spacing / stagger / balance ---
STANCE_WIDTH_MIN = 0.75
STANCE_WIDTH_MAX = 1.35
STANCE_STAGGER_MIN = 0.01
STANCE_STAGGER_MAX = 0.12
STANCE_BALANCE_PASS = 0.06
STANCE_BALANCE_WARN = 0.12

# --- Load: knee / hip / COM ---
KNEE_BEND_TARGET_DEG = 60.0
KNEE_BEND_PASS = (45.0, 75.0)
KNEE_BEND_WARN = (30.0, 90.0)
HIP_DROP_PASS = 0.04  # hip y increase vs stance (loaded = higher y)
HIP_DROP_WARN = 0.02
COM_OFFSET_PASS = 0.05
COM_OFFSET_WARN = 0.10

# --- Set Point: elbow / forearm / wrist ---
ELBOW_SET_TARGET = 90.0
ELBOW_SET_PASS = (75.0, 110.0)
ELBOW_SET_WARN = (60.0, 130.0)
FOREARM_VERTICAL_PASS = 25.0  # deg from vertical
FOREARM_VERTICAL_WARN = 40.0
WRIST_ABOVE_ELBOW_PASS = -0.01  # wrist y - elbow y (≤ means above)
WRIST_ABOVE_ELBOW_WARN = 0.03

# --- Release: extension / wrist snap / alignment ---
ELBOW_RELEASE_PASS_MIN = 150.0
ELBOW_RELEASE_WARN_MIN = 130.0
WRIST_SNAP_PASS = 0.03  # Δ(wrist−elbow) across release→follow
WRIST_SNAP_WARN = 0.015
RELEASE_ALIGN_PASS = 0.06
RELEASE_ALIGN_WARN = 0.12

# --- Follow Through ---
FOLLOW_EXTENSION_PASS = 155.0
FOLLOW_EXTENSION_WARN = 135.0
FOLLOW_WRIST_FLEX_PASS = 0.02
FOLLOW_WRIST_FLEX_WARN = 0.0
FOLLOW_HOLD_PASS_S = 0.25
FOLLOW_HOLD_WARN_S = 0.15
FOLLOW_BALANCE_PASS = 0.08
FOLLOW_BALANCE_WARN = 0.14

# Legacy aliases used by older helpers / overlay
HIP_LEVEL_PASS = 0.04
HIP_LEVEL_WARN = 0.08
TORSO_TILT_PASS = 0.05
TORSO_TILT_WARN = 0.10
BACKWARD_LEAN_PASS = 0.04
BACKWARD_LEAN_WARN = 0.08
ELBOW_FLARE_PASS = 0.04
ELBOW_FLARE_WARN = 0.08
ELBOW_RELEASE_TARGET = 170.0
RELEASE_ABOVE_NOSE_PASS = -0.02
RELEASE_ABOVE_NOSE_WARN = 0.04
RELEASE_ARC_PASS = (45.0, 60.0)
RELEASE_ARC_WARN = (38.0, 68.0)
FOLLOW_WRIST_HIGH_PASS = -0.05
FOLLOW_WRIST_HIGH_WARN = 0.0
WRIST_LOAD_DELTA_PASS = 0.02
HEAD_STABILITY_PASS = 0.03
HEAD_STABILITY_WARN = 0.06

STATUS_PASS = 80
STATUS_WARN = 65

# Primary coaching categories — one per focus phase.
PRIMARY_CATEGORIES = (
    "Stance",
    "Load",
    "Set Point",
    "Release",
    "Follow Through",
)

CATEGORY_PHASE = {
    "Stance": "setup",
    "Load": "knee_load",
    "Set Point": "set_point",
    "Release": "release",
    "Follow Through": "follow_through",
    # Legacy names → same phases
    "Feet & Stance": "setup",
    "Knee Bend": "knee_load",
    "Elbow Alignment": "set_point",
    "Release Point": "release",
    "Release Position": "release",
    "Balance": "setup",
}

# Weighted overall (aligned with Flutter CoachingReportService):
# Release 25%, Balance 20%, Elbow 20%, Lower Body 15%, Follow Through 10%,
# Consistency is computed client-side from score spread.
CATEGORY_WEIGHTS = {
    "Release": 0.25,
    "Release Point": 0.25,
    "Balance": 0.20,
    "Stance": 0.10,  # contributes to balance / lower-body mix
    "Feet & Stance": 0.10,
    "Set Point": 0.20,
    "Elbow Alignment": 0.20,
    "Load": 0.15,
    "Knee Bend": 0.15,
    "Follow Through": 0.10,
    "Ball Position": 0.05,
    "Hand Position": 0.05,
}


def color_for_status(status: str) -> str:
    if status == "PASS":
        return "GREEN"
    if status == "FAIL":
        return "RED"
    return "YELLOW"


def status_from_score(score: int) -> str:
    if score >= STATUS_PASS:
        return "PASS"
    if score >= STATUS_WARN:
        return "WARN"
    return "FAIL"
