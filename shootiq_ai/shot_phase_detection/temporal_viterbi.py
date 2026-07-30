"""Temporal motion HMM (Viterbi) shot-phase classifier.

Classifies phases from landmark *motion over time*:
  knee flexion velocity, elbow extension velocity, wrist/hip/shoulder/
  ankle vertical velocity.

Does NOT pick phases with static angle thresholds (e.g. elbow == 90°).
Angle *levels* appear only as weak context / confidence cues.

Future supervised models can replace this class while keeping the same
PhaseClassifier.predict() contract and FramePhaseLabel schema.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from shot_phase_detection.classifier import PhaseClassifier
from shot_phase_detection.features import TemporalFeatureSeries
from shot_phase_detection.schema import PHASE_ORDER, FramePhaseLabel


def _softmax_row(logits: np.ndarray) -> np.ndarray:
    x = logits - np.max(logits)
    e = np.exp(np.clip(x, -40, 40))
    s = e.sum()
    if s <= 0:
        return np.ones_like(logits) / len(logits)
    return e / s


def _gauss(x: float, mu: float, sigma: float) -> float:
    if sigma <= 1e-9:
        return 0.0
    z = (x - mu) / sigma
    return float(np.exp(-0.5 * z * z))


class TemporalMotionClassifier(PhaseClassifier):
    """Left-to-right HMM over motion emissions + Viterbi decode."""

    name = "temporal_motion_viterbi"
    version = "1.1.0"

    def predict(
        self,
        features: TemporalFeatureSeries,
        *,
        meta: dict[str, Any] | None = None,
    ) -> list[FramePhaseLabel]:
        del meta
        n = features.n
        if n == 0:
            return []
        if n == 1:
            return [
                FramePhaseLabel(
                    frame_number=int(features.video_frames[0]),
                    timestamp=float(features.timestamps[0]),
                    shot_phase="setup",
                    confidence=0.5,
                    sample_index=0,
                )
            ]

        events = self._detect_motion_events(features)
        emissions = self._emission_logits(features, events)  # (n, n_phases)
        path, conf = self._viterbi(emissions)

        labels: list[FramePhaseLabel] = []
        for i, phase_i in enumerate(path):
            labels.append(
                FramePhaseLabel(
                    frame_number=int(features.video_frames[i]),
                    timestamp=float(features.timestamps[i]),
                    shot_phase=PHASE_ORDER[phase_i],
                    confidence=float(conf[i]),
                    sample_index=i,
                )
            )
        return labels

    # ------------------------------------------------------------------
    # Motion events (velocity / trajectory based)
    # ------------------------------------------------------------------
    def _detect_motion_events(self, f: TemporalFeatureSeries) -> dict[str, int]:
        n = f.n
        knee_v = f.knee_flex_vel
        elbow_v = f.elbow_ext_vel
        wrist_vy = f.wrist_vy
        wrist_y = f.wrist_y

        # Load: deepest knee flexion BEFORE the shot's real upward drive.
        # Capped at the wrist's first sustained rise (+ a small buffer for the
        # natural overlap where the arm starts lifting just before the legs
        # finish settling) so a LATER, unrelated knee-bend — a landing-
        # absorption crouch after release, or the start of a next rep — can
        # never be mistaken for the actual pre-shot load. Without this cap,
        # whichever knee-bend is biggest anywhere in the clip wins, even if
        # it happens well after the ball is already gone.
        median_dt = float(np.median(f.dt)) if f.dt.size else 1.0 / 30.0
        clip_fps = 1.0 / max(median_dt, 1e-3)
        rise_onset = self._first_sustained_rise(wrist_vy)
        load = self._load_index(knee_v, f.knee_flexion, rise_onset=rise_onset, fps=clip_fps)

        # Elbow extension burst after load (start of shot upward).
        # Bounded by real time (~1s), not a fraction of the whole clip: a
        # `n // 3` window is fine on a short ~2s clip but balloons past 5
        # seconds on a longer recording, easily reaching an unrelated later
        # arm motion (e.g. a big follow-through flourish) whose extension
        # velocity happens to be even bigger than the real one — which then
        # drags the release search past the true release with it, since
        # `_release_index` starts its own search at this point.
        search_hi = min(n - 1, load + max(3, int(round(1.0 * clip_fps))))
        if search_hi > load:
            ext_peak = load + int(np.argmax(elbow_v[load : search_hi + 1]))
        else:
            ext_peak = min(n - 1, load + 1)

        # Release: wrist upward-velocity zero-crossing after extension burst,
        # snapped to nearby wrist height peak (min y). Pure motion timing.
        release = self._release_index(
            wrist_vy, wrist_y, elbow_v, load, ext_peak, fps=clip_fps
        )

        # Gather onset: when knee flexion velocity stays positive leading into load.
        gather = self._gather_index(knee_v, wrist_vy, load)

        # Follow end: after release, wrist drop + lost upward support.
        follow_end = self._follow_end_index(f, release)

        return {
            "gather": gather,
            "load": load,
            "ext_peak": ext_peak,
            "release": release,
            "follow_end": follow_end,
        }

    def _first_sustained_rise(
        self,
        wrist_vy: np.ndarray,
        threshold: float = 0.3,
        run_frames: int = 3,
    ) -> int | None:
        """First frame where the wrist begins a real, sustained rise (not
        idle jitter/dribbling). 0.3 sits well above typical idle wrist
        movement (< 0.2 in these units) and below a real shot's rise
        (> 0.4-0.5 sustained) — consistent with this module's own emission
        calibration, which already treats ~0.35 as "rising into the shot"
        (see the set_point score in `_emission_logits`). Returns None if no
        such rise exists (falls back to no cap)."""
        n = wrist_vy.size
        for i in range(max(0, n - run_frames)):
            if np.all(wrist_vy[i : i + run_frames] > threshold):
                return i
        return None

    def _load_index(
        self,
        knee_v: np.ndarray,
        knee_flex: np.ndarray,
        rise_onset: int | None = None,
        pad_seconds: float = 0.17,
        fps: float = 30.0,
    ) -> int:
        n = knee_v.size
        # Deepest flexion in the first 80% of the clip, capped at the wrist's
        # first real rise (+ small buffer) when we have one. Using the
        # flexion LEVEL (not a velocity zero-crossing) is robust to a bend
        # that has more than one local speed bump on the way down — the
        # velocity-based search used to lock onto whichever bump came first
        # and then run out of room before reaching the true bottom.
        hi = max(1, int(n * 0.8))
        if rise_onset is not None:
            pad = max(1, int(round(pad_seconds * fps)))
            hi = max(1, min(hi, rise_onset + pad))
        return int(np.argmax(knee_flex[:hi]))

    def _release_index(
        self,
        wrist_vy: np.ndarray,
        wrist_y: np.ndarray,
        elbow_v: np.ndarray,
        load: int,
        ext_peak: int,
        fps: float = 30.0,
    ) -> int:
        n = wrist_vy.size
        # Search from `load` directly rather than gating on `ext_peak`: real
        # elbow-extension motion often has more than one local speed bump
        # (a wind-up before the final drive), so `ext_peak` can itself land
        # on a later, larger-but-irrelevant bump — gating the release search
        # on it would skip straight past the true wrist-velocity crossing.
        # The `wrist_vy > 0.02` condition below already guards against
        # detecting a release while the wrist hasn't really started rising,
        # so this doesn't need a second, fragile pre-filter.
        #
        # `end` is bounded by real time (~2s), not a fraction of the clip
        # (`n // 4`) — that fraction was tuned around short ~2s clips and
        # silently shrinks below the real load-to-release duration on a
        # short clip once `start` moved earlier (from `ext_peak` to `load`),
        # truncating the search before it ever reached the true crossing.
        start = load
        end = min(n - 1, start + max(4, int(round(2.0 * fps))))
        if end <= start:
            return min(n - 1, load + 1)

        # Zero-crossing: wrist_vy goes from rising (+) to flat/falling.
        cross = None
        for i in range(start, end):
            if wrist_vy[i] > 0.02 and wrist_vy[min(i + 1, n - 1)] <= 0.02:
                cross = i + 1 if wrist_vy[min(i + 1, n - 1)] <= 0.02 else i
                break
        if cross is None:
            # Soft fallback: min wrist_vy magnitude near height peak after ext.
            local = wrist_y[start : end + 1]
            cross = start + int(np.argmin(local))

        # Snap to wrist height peak within ±2 samples (hand apex ≈ ball release).
        lo = max(start, cross - 2)
        hi = min(n - 1, cross + 2)
        peak = lo + int(np.argmin(wrist_y[lo : hi + 1]))

        # Prefer peak if it is at/after extension burst and wrist still high.
        if peak >= ext_peak:
            return peak
        return int(np.clip(cross, load, n - 1))

    def _gather_index(
        self,
        knee_v: np.ndarray,
        wrist_vy: np.ndarray,
        load: int,
    ) -> int:
        if load <= 1:
            return 0
        # Walk backward while still loading (knee_v > 0) or wrist starting up.
        gather = 0
        for i in range(load - 1, -1, -1):
            loading = knee_v[i] > 8.0  # deg/s
            rising = wrist_vy[i] > 0.05
            if not loading and not rising and knee_v[i] < 4.0:
                gather = i + 1
                break
        else:
            gather = max(0, load // 5)
        if gather >= load:
            gather = max(0, load - max(1, load // 4))
        return gather

    def _follow_end_index(self, f: TemporalFeatureSeries, release: int) -> int:
        n = f.n
        if release >= n - 1:
            return n - 1
        # End when wrist has dropped meaningfully and elbow extension velocity
        # is no longer supporting a hold (temporal, not static angle gate).
        wrist0 = f.wrist_y[release]
        median_dt = float(np.median(f.dt)) if f.dt.size else 1.0 / 30.0
        min_hold = max(2, int(round(0.25 / max(median_dt, 1e-3))))  # ≥ ~0.25s
        max_scan = min(n - 1, release + max(min_hold + 2, n // 3))
        end = min(n - 1, release + min_hold)
        for i in range(release + 1, max_scan + 1):
            dropped = f.wrist_y[i] > wrist0 + 0.10
            collapsing = f.elbow_ext_vel[i] < -55.0  # deg/s
            if i >= release + min_hold and dropped and collapsing:
                end = i
                break
            end = i
        return end

    # ------------------------------------------------------------------
    # Emissions
    # ------------------------------------------------------------------
    def _emission_logits(
        self,
        f: TemporalFeatureSeries,
        events: dict[str, int],
    ) -> np.ndarray:
        n = f.n
        k = len(PHASE_ORDER)
        logits = np.zeros((n, k), dtype=float)

        gather = events["gather"]
        load = events["load"]
        ext_peak = events["ext_peak"]
        release = events["release"]
        follow_end = events["follow_end"]

        # Soft span centers for gaussian proximity boosts.
        # Set Point = rise after load until just before release (ball set).
        spans = {
            "setup": (0, max(0, gather - 1)),
            "gather": (gather, max(gather, load - 1)),
            "knee_load": (load, load),
            "set_point": (min(n - 1, load + 1), max(load + 1, release - 1)),
            "release": (release, release),
            "follow_through": (min(n - 1, release + 1), follow_end),
            "landing": (min(n - 1, follow_end + 1), n - 1),
        }

        for i in range(n):
            kv = float(f.knee_flex_vel[i])
            ev = float(f.elbow_ext_vel[i])
            wv = float(f.wrist_vy[i])
            hv = float(f.hip_vy[i])
            sv = float(f.shoulder_vy[i])

            # Motion-signature scores (not static angle thresholds).
            scores = {
                # Stance: quiet lower body / hands
                "setup": (
                    _gauss(kv, 0.0, 25.0)
                    + _gauss(wv, 0.0, 0.25)
                    + _gauss(ev, 0.0, 40.0)
                ),
                # Gather: loading (positive knee flex vel)
                "gather": (
                    _gauss(kv, 40.0, 35.0)
                    + _gauss(max(wv, 0.0), 0.15, 0.25)
                ),
                # Load: flexion velocity near zero after loading (turnaround)
                "knee_load": (
                    _gauss(kv, 0.0, 20.0)
                    + _gauss(abs(i - load), 0.0, 1.5) * 2.0
                ),
                # Set Point: rising into the shot — wrist up, elbow beginning to extend
                "set_point": (
                    _gauss(kv, -50.0, 45.0)
                    + _gauss(wv, 0.35, 0.3)
                    + _gauss(ev, 40.0, 50.0)
                    + _gauss(hv, 0.15, 0.25)
                ),
                # Release: wrist vertical vel ~ 0 at apex after extension burst
                "release": (
                    _gauss(wv, 0.0, 0.12)
                    + _gauss(abs(i - release), 0.0, 1.2) * 2.5
                    + _gauss(ev, 20.0, 50.0)
                ),
                # Follow: after release — wrist no longer rising, elbow hold/slow drop
                "follow_through": (
                    _gauss(max(-wv, 0.0), 0.2, 0.3)
                    + _gauss(ev, 0.0, 60.0)
                    + (0.8 if release < i <= follow_end else 0.0)
                ),
                # Landing: settling; ankles/hips quieting after follow
                "landing": (
                    _gauss(kv, 0.0, 30.0)
                    + _gauss(wv, 0.0, 0.3)
                    + _gauss(sv, 0.0, 0.25)
                    + (0.6 if i > follow_end else 0.0)
                ),
            }

            for pi, key in enumerate(PHASE_ORDER):
                start, end = spans[key]
                # Proximity to expected span
                if start <= i <= end:
                    prox = 1.6
                else:
                    dist = min(abs(i - start), abs(i - end))
                    prox = _gauss(dist, 0.0, 3.0)
                logits[i, pi] = scores[key] + prox

            # Shoulder rise couples with set-point / release timing
            logits[i, PHASE_ORDER.index("set_point")] += 0.15 * _gauss(sv, 0.2, 0.3)
            logits[i, PHASE_ORDER.index("release")] += 0.1 * _gauss(
                abs(i - ext_peak), 2.0, 3.0
            )

        return logits

    # ------------------------------------------------------------------
    # Viterbi (left-to-right)
    # ------------------------------------------------------------------
    def _viterbi(self, emissions: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        n, k = emissions.shape
        # Transition: stay, advance +1, rare skip +2. No going backward.
        log_trans = np.full((k, k), -1e9)
        for i in range(k):
            log_trans[i, i] = np.log(0.55)
            if i + 1 < k:
                log_trans[i, i + 1] = np.log(0.40)
            if i + 2 < k:
                log_trans[i, i + 2] = np.log(0.05)

        log_emit = np.log(np.clip(emissions, 1e-9, None))
        # Normalize emissions per frame into probabilities first for stable conf.
        emit_prob = np.zeros_like(emissions)
        for i in range(n):
            emit_prob[i] = _softmax_row(emissions[i])
        log_emit = np.log(np.clip(emit_prob, 1e-9, None))

        dp = np.full((n, k), -1e9)
        bp = np.zeros((n, k), dtype=int)
        dp[0] = log_emit[0]
        # Prefer starting in stance
        dp[0, 0] += np.log(0.9)
        for j in range(1, k):
            dp[0, j] += np.log(0.1 / (k - 1))

        for t in range(1, n):
            for j in range(k):
                scores = dp[t - 1] + log_trans[:, j]
                bp[t, j] = int(np.argmax(scores))
                dp[t, j] = scores[bp[t, j]] + log_emit[t, j]

        path = np.zeros(n, dtype=int)
        path[-1] = int(np.argmax(dp[-1]))
        for t in range(n - 2, -1, -1):
            path[t] = bp[t + 1, path[t + 1]]

        # Confidence = posterior mass of chosen state at each frame.
        conf = np.array([float(emit_prob[t, path[t]]) for t in range(n)])
        # Mild path-consistency bonus
        conf = np.clip(conf * 0.85 + 0.15, 0.05, 0.99)
        return path, conf
