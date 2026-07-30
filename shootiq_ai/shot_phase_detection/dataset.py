"""Training-data schema for future supervised shot-phase models.

Design goals
------------
- Learn phase *timing* from many elite shooters — not copy one player's form.
- Labels are phase boundaries / per-frame classes, independent of score targets.
- Feature matrix comes from TemporalFeatureSeries.to_training_matrix().

Suggested workflow (future)
---------------------------
1. Manually label videos → LabeledShotExample JSONL
2. Train sequence model (CRF / BiLSTM / Transformer) on feature windows
3. Export weights; wrap in SupervisedSequenceClassifier(PhaseClassifier)
4. set_default_classifier(trained) without changing biomechanics analyzers
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

from shot_phase_detection.schema import PHASE_ORDER, FramePhaseLabel, normalize_phase_key


@dataclass
class LabeledShotExample:
    """One manually labeled shooting clip for phase-detector training."""

    example_id: str
    video_path: str
    shooter_id: str | None = None
    skill_tier: str | None = None  # e.g. "elite", "college", "youth"
    fps: float = 30.0
    sample_every: int = 1
    # Per-frame ground truth (frame_number, shot_phase)
    labels: list[FramePhaseLabel] = field(default_factory=list)
    notes: str = ""
    # Optional: do NOT store biomechanics scores here — phases ≠ form quality.
    meta: dict[str, Any] = field(default_factory=dict)

    def to_json(self) -> dict[str, Any]:
        return {
            "example_id": self.example_id,
            "video_path": self.video_path,
            "shooter_id": self.shooter_id,
            "skill_tier": self.skill_tier,
            "fps": self.fps,
            "sample_every": self.sample_every,
            "labels": [label.to_json() for label in self.labels],
            "notes": self.notes,
            "meta": self.meta,
            "phase_taxonomy": list(PHASE_ORDER),
            "labeling_guide": (
                "Label the temporal phase of the shot only. "
                "Do not score mechanics. Prefer diverse elite shooters "
                "so the model learns phase structure, not a single form."
            ),
        }

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> LabeledShotExample:
        labels = [
            FramePhaseLabel.from_json(item)
            for item in (data.get("labels") or [])
            if isinstance(item, dict)
        ]
        return cls(
            example_id=str(data.get("example_id", "")),
            video_path=str(data.get("video_path", "")),
            shooter_id=data.get("shooter_id"),
            skill_tier=data.get("skill_tier"),
            fps=float(data.get("fps") or 30.0),
            sample_every=int(data.get("sample_every") or 1),
            labels=labels,
            notes=str(data.get("notes") or ""),
            meta=dict(data.get("meta") or {}),
        )


def validate_label_sequence(labels: list[FramePhaseLabel]) -> list[str]:
    """Return warnings for non-monotonic / unknown phase sequences."""
    warnings: list[str] = []
    order_index = {key: i for i, key in enumerate(PHASE_ORDER)}
    prev = -1
    for label in labels:
        key = normalize_phase_key(label.shot_phase)
        if key not in order_index:
            warnings.append(f"Unknown phase {label.shot_phase!r} @ frame {label.frame_number}")
            continue
        idx = order_index[key]
        if idx < prev - 0:  # allow stay; forbid moving backward
            if idx < prev:
                warnings.append(
                    f"Phase regresses to {key} @ frame {label.frame_number} "
                    f"(was index {prev})"
                )
        prev = max(prev, idx)
    return warnings


# Placeholder for a future trained implementation.
class SupervisedSequenceClassifierPlaceholder:
    """
    Document-only stub — implement when labeled elite-shooter data exists.

    Expected interface:
        class SupervisedSequenceClassifier(PhaseClassifier):
            def __init__(self, weights_path: str): ...
            def predict(self, features, meta=None) -> list[FramePhaseLabel]: ...
    """

    training_target = (
        "Sequence labeling over TemporalFeatureSeries.to_training_matrix(); "
        "cross-entropy / CRF loss on PHASE_ORDER classes; early-stop on "
        "held-out shooters (leave-one-shooter-out) to avoid form cloning."
    )
