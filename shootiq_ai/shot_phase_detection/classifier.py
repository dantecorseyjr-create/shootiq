"""Swappable shot-phase classifier interface.

Production today: TemporalMotionClassifier (motion HMM / Viterbi).
Future: SupervisedSequenceClassifier trained on labeled elite-shooter clips.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from shot_phase_detection.features import TemporalFeatureSeries
from shot_phase_detection.schema import FramePhaseLabel


class PhaseClassifier(ABC):
    """
    Classify each pose sample into exactly one shot phase.

    Implementations must use temporal / motion information.
    They must NOT gate phases on static joint-angle thresholds alone.
    """

    name: str = "base"
    version: str = "0"

    @abstractmethod
    def predict(
        self,
        features: TemporalFeatureSeries,
        *,
        meta: dict[str, Any] | None = None,
    ) -> list[FramePhaseLabel]:
        """Return one label per sample index (aligned with features)."""

    def describe(self) -> dict[str, Any]:
        return {"name": self.name, "version": self.version}


_DEFAULT: PhaseClassifier | None = None


def get_default_classifier() -> PhaseClassifier:
    """Singleton production classifier (motion Viterbi)."""
    global _DEFAULT
    if _DEFAULT is None:
        from shot_phase_detection.temporal_viterbi import TemporalMotionClassifier

        _DEFAULT = TemporalMotionClassifier()
    return _DEFAULT


def set_default_classifier(classifier: PhaseClassifier) -> None:
    """Override for tests or a future trained model."""
    global _DEFAULT
    _DEFAULT = classifier
