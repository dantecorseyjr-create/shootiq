"""Canonical shot-phase schema (machine keys + display labels)."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

# Machine keys — stable for analyzers / stored history.
# Evaluation focus phases: Stance, Load, Set Point, Release, Follow Through.
# Gather / Landing remain transitional for temporal continuity.
PHASE_ORDER = (
    "setup",
    "gather",
    "knee_load",
    "set_point",
    "release",
    "follow_through",
    "landing",
)

# Coach-facing labels (user-facing timeline).
PHASE_LABELS = {
    "setup": "Stance",
    "gather": "Gather",
    "knee_load": "Load",
    "set_point": "Set Point",
    "release": "Release",
    "follow_through": "Follow Through",
    "landing": "Landing",
}

PHASE_COLORS = {
    "setup": "#60A5FA",
    "gather": "#34D399",
    "knee_load": "#FBBF24",
    "set_point": "#FB923C",
    "release": "#F87171",
    "follow_through": "#C084FC",
    "landing": "#94A3B8",
}

# What each focus phase evaluates (coaching contract).
PHASE_EVALUATION = {
    "setup": ("foot spacing", "foot stagger", "body balance"),
    "knee_load": ("knee angle", "hip position", "center of mass"),
    "set_point": ("elbow angle", "forearm angle", "wrist position"),
    "release": ("elbow extension", "wrist snap", "body alignment"),
    "follow_through": (
        "arm extension",
        "wrist flexion",
        "body balance",
        "duration follow-through is held",
    ),
}

# Future / alternate names → machine keys.
PHASE_ALIASES = {
    "stance": "setup",
    "load": "knee_load",
    "knee load": "knee_load",
    "set": "set_point",
    "setpoint": "set_point",
    "upward": "set_point",
    "upward_motion": "set_point",
    "follow": "follow_through",
    "follow-through": "follow_through",
}


def normalize_phase_key(key: str | None) -> str:
    if not key:
        return "setup"
    raw = key.strip().lower().replace("-", "_").replace(" ", "_")
    if raw in PHASE_ORDER:
        return raw
    return PHASE_ALIASES.get(raw, raw if raw in PHASE_ORDER else "setup")


@dataclass(frozen=True)
class FramePhaseLabel:
    """One classified frame — persisted for scrubbing / future training."""

    frame_number: int
    timestamp: float
    shot_phase: str
    confidence: float
    sample_index: int | None = None

    def to_json(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["shot_phase"] = normalize_phase_key(self.shot_phase)
        payload["phase_label"] = PHASE_LABELS.get(
            payload["shot_phase"], self.shot_phase
        )
        payload["confidence"] = round(float(self.confidence), 4)
        payload["timestamp"] = round(float(self.timestamp), 4)
        return payload

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> FramePhaseLabel:
        return cls(
            frame_number=int(data.get("frame_number", 0)),
            timestamp=float(data.get("timestamp", 0.0)),
            shot_phase=normalize_phase_key(
                data.get("shot_phase") or data.get("phase")
            ),
            confidence=float(data.get("confidence", 0.0)),
            sample_index=(
                int(data["sample_index"])
                if data.get("sample_index") is not None
                else None
            ),
        )


def format_timestamp(seconds: float) -> str:
    total = max(0, int(round(seconds)))
    minutes, secs = divmod(total, 60)
    return f"{minutes:02d}:{secs:02d}"
