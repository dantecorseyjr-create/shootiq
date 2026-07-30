"""Fast video prep: resize to vertical 720p @ 30fps + optional slow-mo."""

from __future__ import annotations

import subprocess
import time
from pathlib import Path
from typing import Callable

import imageio_ffmpeg

# Speed-optimized vertical canvas (720p 9:16). Overlay can still run later.
TARGET_WIDTH = 720
TARGET_HEIGHT = 1280
TARGET_FPS = 30
SLOW_MOTION_FACTOR = 0.5
# Analyze every Nth frame for MediaPipe (keep in sync with pose_pipeline).
POSE_SAMPLE_EVERY = 1

ProgressCb = Callable[[str, int], None]


def _ffmpeg() -> str:
    return imageio_ffmpeg.get_ffmpeg_exe()


def _run(cmd: list[str]) -> None:
    print("ffmpeg:", " ".join(cmd))
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "")[-1200:]
        raise RuntimeError(f"ffmpeg failed: {err}")


def standardize_vertical(
    input_path: str | Path,
    output_path: str | Path,
    on_progress: ProgressCb | None = None,
) -> Path:
    """
    Convert to MP4 720x1280 (9:16) at 30fps for fast analysis.

    Center-crops to fill while keeping the player in frame.
    """
    src = Path(input_path)
    dst = Path(output_path)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if on_progress:
        on_progress("extracting_frames", 20)

    t0 = time.perf_counter()
    vf = (
        f"fps={TARGET_FPS},"
        f"scale={TARGET_WIDTH}:{TARGET_HEIGHT}:force_original_aspect_ratio=increase,"
        f"crop={TARGET_WIDTH}:{TARGET_HEIGHT}"
    )
    # Deterministic x264 (single-thread) so the same upload re-encodes to the
    # same pixels — multithreaded ultrafast was a source of score drift.
    cmd = [
        _ffmpeg(),
        "-y",
        "-i",
        str(src),
        "-vf",
        vf,
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "20",
        "-threads",
        "1",
        "-x264-params",
        "threads=1:sliced-threads=0:sync-lookahead=0:rc-lookahead=10",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        "-an",
        str(dst),
    ]
    _run(cmd)
    if not dst.exists() or dst.stat().st_size <= 0:
        raise RuntimeError(f"Standardized video missing: {dst}")
    elapsed = time.perf_counter() - t0
    print(
        f"Frame extraction completed ({elapsed:.2f}s) → {dst} "
        f"size={dst.stat().st_size}"
    )
    return dst


def make_slow_motion(
    input_path: str | Path,
    output_path: str | Path,
    factor: float = SLOW_MOTION_FACTOR,
) -> Path:
    """Create a 0.5x slow-motion MP4 (used in background, not on report path)."""
    src = Path(input_path)
    dst = Path(output_path)
    dst.parent.mkdir(parents=True, exist_ok=True)
    speed = max(0.1, min(factor, 1.0))
    pts = 1.0 / speed
    t0 = time.perf_counter()
    cmd = [
        _ffmpeg(),
        "-y",
        "-i",
        str(src),
        "-filter:v",
        f"setpts={pts}*PTS",
        "-c:v",
        "libx264",
        "-preset",
        "ultrafast",
        "-crf",
        "23",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        "-an",
        str(dst),
    ]
    _run(cmd)
    if not dst.exists() or dst.stat().st_size <= 0:
        raise RuntimeError(f"Slow-motion video missing: {dst}")
    print(
        f"Slow-motion completed ({time.perf_counter() - t0:.2f}s) → {dst} "
        f"factor={speed}"
    )
    return dst
