#!/usr/bin/env python3
"""CLI smoke test for ShootIQ Step 4 MediaPipe Pose foundation.

Usage:
  python run_pose_step4.py /path/to/shot.mp4
  python run_pose_step4.py /path/to/shot.mp4 --sample-every 2
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="ShootIQ Step 4 pose detection test")
    parser.add_argument("video", type=str, help="Path to a basketball shooting video")
    parser.add_argument(
        "--sample-every",
        type=int,
        default=None,
        help="Process every Nth frame (default from pose_pipeline.POSE_SAMPLE_EVERY)",
    )
    parser.add_argument(
        "--out",
        type=str,
        default=None,
        help="Optional output directory",
    )
    args = parser.parse_args()

    video = Path(args.video).expanduser().resolve()
    if not video.exists():
        print(f"ERROR: video not found: {video}")
        return 1

    from pose_pipeline import run_pose_detection

    result = run_pose_detection(
        video_path=video,
        output_dir=args.out,
        sample_every=args.sample_every,
        write_overlay=True,
    )

    print()
    print("=== Step 4 results ===")
    print("output_dir:", result["output_dir"])
    print("original_video:", result["original_video"])
    print("pose_data_json:", result["pose_data_json"])
    print("shot_angles_json:", result.get("shot_angles_json"))
    print(
        "follow_through_analysis_json:",
        result.get("follow_through_analysis_json"),
    )
    print("skeleton_overlay:", result["skeleton_overlay"])
    print("frames_with_pose:", result["frames_with_pose"])
    print("detection_rate%:", result["pose_detection_rate"])
    print("MediaPipe detected player:", "YES" if result["mediapipe_ok"] else "NO")
    return 0 if result["mediapipe_ok"] else 2


if __name__ == "__main__":
    sys.exit(main())
