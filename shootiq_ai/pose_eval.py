"""Shared pose measurements for phase-scoped biomechanics rubrics."""

from __future__ import annotations

import math
from typing import Any

from pose_utils import calculate_angle, dist3, shooting_side, side_points, xy, xyz


def foot_spacing_ratio(frame: dict[str, Any]) -> float | None:
    # 3D distance, not x-only: from a side camera angle the left/right ankles
    # (and shoulders) sit almost inline with the lens, so their on-screen
    # x-difference collapses toward zero even though the real spacing is
    # normal — dividing by that near-zero denominator blew this up to 50x+
    # on side-view clips instead of the expected ~1x shoulder widths.
    l_ankle, r_ankle = xyz(frame, "left_ankle"), xyz(frame, "right_ankle")
    l_sh, r_sh = xyz(frame, "left_shoulder"), xyz(frame, "right_shoulder")
    if not (l_ankle and r_ankle and l_sh and r_sh):
        return None
    shoulder_w = dist3(l_sh, r_sh) or 0.2
    return dist3(l_ankle, r_ankle) / shoulder_w


def foot_stagger(frame: dict[str, Any]) -> float | None:
    side = shooting_side(frame)
    shoot = xy(frame, f"{side}_ankle")
    guide = xy(frame, f"{'left' if side == 'right' else 'right'}_ankle")
    if not shoot or not guide:
        return None
    # Positive when guide foot is lower on screen (shooting foot ahead / higher).
    return guide[1] - shoot[1]


def body_balance(frame: dict[str, Any]) -> dict[str, float] | None:
    """Torso vs hip/ankle stack — smaller is more balanced."""
    l_hip, r_hip = xy(frame, "left_hip"), xy(frame, "right_hip")
    l_sh, r_sh = xy(frame, "left_shoulder"), xy(frame, "right_shoulder")
    l_an, r_an = xy(frame, "left_ankle"), xy(frame, "right_ankle")
    if not (l_hip and r_hip and l_sh and r_sh):
        return None
    mid_hip_x = (l_hip[0] + r_hip[0]) / 2
    mid_sh_x = (l_sh[0] + r_sh[0]) / 2
    tilt = abs(mid_sh_x - mid_hip_x)
    hip_level = abs(l_hip[1] - r_hip[1])
    lean = 0.0
    if l_an and r_an:
        mid_an_x = (l_an[0] + r_an[0]) / 2
        lean = abs(mid_sh_x - mid_an_x) - abs(mid_hip_x - mid_an_x)
    return {
        "torso_tilt": tilt,
        "hip_level": hip_level,
        "backward_lean": lean,
        "balance_score": tilt + 0.5 * hip_level + max(0.0, lean),
    }


def center_of_mass_offset(frame: dict[str, Any]) -> float | None:
    """
    Approximate COM lateral offset: mid-shoulder/hip vs mid-ankle.
    0 = stacked over the base.
    """
    l_hip, r_hip = xy(frame, "left_hip"), xy(frame, "right_hip")
    l_sh, r_sh = xy(frame, "left_shoulder"), xy(frame, "right_shoulder")
    l_an, r_an = xy(frame, "left_ankle"), xy(frame, "right_ankle")
    if not (l_hip and r_hip and l_an and r_an):
        return None
    mid_hip = (l_hip[0] + r_hip[0]) / 2
    mid_an = (l_an[0] + r_an[0]) / 2
    mid_sh = ((l_sh[0] + r_sh[0]) / 2) if l_sh and r_sh else mid_hip
    com_x = 0.55 * mid_hip + 0.45 * mid_sh
    return abs(com_x - mid_an)


def hip_height(frame: dict[str, Any]) -> float | None:
    """Normalized hip y (smaller = higher on screen / more loaded uprightness)."""
    l_hip, r_hip = xy(frame, "left_hip"), xy(frame, "right_hip")
    if l_hip and r_hip:
        return (l_hip[1] + r_hip[1]) / 2
    if l_hip or r_hip:
        return (l_hip or r_hip)[1]
    return None


def knee_joint_and_bend(frame: dict[str, Any]) -> tuple[float, float] | None:
    side = shooting_side(frame)
    pts = side_points(frame, side, ("hip", "knee", "ankle"))
    if pts is None:
        return None
    from pose_utils import bend_from_standing

    angle = calculate_angle(pts[0], pts[1], pts[2])
    return angle, bend_from_standing(angle)


def elbow_angle(frame: dict[str, Any]) -> float | None:
    side = shooting_side(frame)
    pts = side_points(frame, side, ("shoulder", "elbow", "wrist"))
    if pts is None:
        return None
    return calculate_angle(pts[0], pts[1], pts[2])


def forearm_angle_from_vertical(frame: dict[str, Any]) -> float | None:
    """Degrees from vertical (0 = forearm straight up)."""
    side = shooting_side(frame)
    elbow = xy(frame, f"{side}_elbow")
    wrist = xy(frame, f"{side}_wrist")
    if not elbow or not wrist:
        return None
    dx = wrist[0] - elbow[0]
    dy = wrist[1] - elbow[1]  # +down
    # Angle from upward vertical (-y).
    return abs(math.degrees(math.atan2(dx, -dy + 1e-6)))


def wrist_position_vs_elbow(frame: dict[str, Any]) -> float | None:
    """Wrist y − elbow y (negative = wrist above elbow)."""
    side = shooting_side(frame)
    elbow = xy(frame, f"{side}_elbow")
    wrist = xy(frame, f"{side}_wrist")
    if not elbow or not wrist:
        return None
    return wrist[1] - elbow[1]


def body_alignment(frame: dict[str, Any]) -> float | None:
    """Shoulder–hip–ankle stack residual (lower is better)."""
    bal = body_balance(frame)
    if bal is None:
        return None
    return bal["balance_score"]


def wrist_flexion_proxy(frame: dict[str, Any]) -> float | None:
    """
    Goose-neck proxy: wrist below elbow after release (positive = flexed down).
    Uses wrist y − elbow y in image coords.
    """
    delta = wrist_position_vs_elbow(frame)
    if delta is None:
        return None
    return delta  # larger positive after release ≈ wrist dropped/flexed
